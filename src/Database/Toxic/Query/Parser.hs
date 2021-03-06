{-# LANGUAGE OverloadedStrings #-}

module Database.Toxic.Query.Parser where

import Database.Toxic.Types as Toxic
import Database.Toxic.Query.AST

import Control.Applicative ((<$>), (*>), (<*), (<*>))
import Control.Monad
import Data.List (nub)
import Data.Monoid
import qualified Data.Text as T
import qualified Data.Vector as V
import Text.Parsec
import Text.Parsec.Combinator
import Text.Parsec.Expr
import Text.Parsec.Language
import qualified Text.Parsec.Token as P

type CharParser a = Parsec String () a

reservedOperators = ["<>", "*","+",">",">=","=","<=","<"]
reservedOperatorCharacters = nub $ concat reservedOperators

sqlLanguageDef = P.LanguageDef {
  P.commentStart = "",
  P.commentEnd = "",
  P.commentLine = "--",
  P.nestedComments = False,
  P.identStart = letter <|> char '_',
  P.identLetter = alphaNum <|> char '_',
  P.opStart = oneOf $ reservedOperatorCharacters,
  P.opLetter = oneOf $ reservedOperatorCharacters,
  P.reservedNames = [],
  P.reservedOpNames = reservedOperators,
  P.caseSensitive = False
  }

lexer = P.makeTokenParser sqlLanguageDef

integer :: CharParser Literal
integer = LInt <$> P.integer lexer

identifier :: CharParser T.Text
identifier = T.pack <$> P.identifier lexer

keyword :: String -> CharParser ()
keyword text = P.reserved lexer text

operator :: String -> CharParser ()
operator text = P.reservedOp lexer text

commaSep = P.commaSep lexer
commaSep1 = P.commaSep1 lexer

operator_table =
  let mkUnop name unop = prefix name (EUnop unop)
      mkBinop name binop = binary name (EBinop binop) AssocLeft
  in [ [ mkUnop "not" UnopNot ],
       [ mkBinop "*" BinopTimes, mkBinop "/" BinopDividedBy ],
       [ mkBinop "+" BinopPlus, mkBinop "-" BinopMinus ],
       [
         mkBinop ">=" BinopGreaterOrEqual,
         mkBinop ">" BinopGreater,
         mkBinop "<" BinopLess,
         mkBinop "<=" BinopLessOrEqual,
         mkBinop "=" BinopEqual,
         mkBinop "<>" BinopUnequal
       ]
     ]

binary name fun assoc = Infix (operator name *> return fun) assoc
prefix name fun = Prefix (operator name *> return fun)
postfix name fun = Postfix (operator name *> return fun)

parens = P.parens lexer

union_all :: CharParser ()
union_all = keyword "union" *> keyword "all"

literal :: CharParser Literal
literal =
  let true = keyword "true" *> return (LBool True)
      false = keyword "false" *> return (LBool False)
      null = keyword "null" *> return LNull
  in true <|> false <|> null <|> integer

case_condition :: CharParser (Condition, Expression)
case_condition = do
  keyword "when"
  condition <- expression
  keyword "then"
  result <- expression
  return (condition, result)

case_else :: CharParser Expression
case_else = keyword "else" *> expression

case_when_expression :: CharParser Expression
case_when_expression = do
  keyword "case"
  conditions <- many $ case_condition
  else_case <- optionMaybe case_else
  keyword "end"
  return $ ECase (V.fromList conditions) else_case

not_expression :: CharParser Expression
not_expression = do
  keyword "not"
  x <- expression
  return $ EUnop UnopNot x
  
variable :: CharParser Expression
variable = EVariable <$> identifier

term :: CharParser Expression
term =
        try(ELiteral <$> literal)
    <|> case_when_expression
    <|> try function
    <|> variable
    <|> parens expression
    <?> "term"

expression :: CharParser Expression
expression = buildExpressionParser operator_table term

rename_clause :: CharParser T.Text
rename_clause = keyword "as" *> identifier

select_item :: CharParser Expression
select_item = do 
  x <- expression
  rename <- optionMaybe rename_clause
  return $ case rename of
    Just name -> ERename x name
    Nothing -> x

select_clause :: CharParser (ArrayOf Expression)
select_clause = do
  keyword "select"
  V.fromList <$> commaSep1 select_item

group_by_clause :: CharParser (ArrayOf Expression)
group_by_clause = do
  keyword "group"
  keyword "by"
  expressions <- V.fromList <$> commaSep1 expression
  return expressions

order_by_clause :: CharParser (ArrayOf (Expression, StreamOrder))
order_by_clause =
  let order_by_expression :: CharParser (Expression, StreamOrder)
      order_by_expression =
        let streamOrder :: CharParser StreamOrder
            streamOrder =
                  ((keyword "asc" <|> keyword "ascending") *> return Ascending)
              <|> ((keyword "desc" <|> keyword "descending") *> return Descending)
              <|> return Ascending
        in do
          expression <- expression
          order <- streamOrder
          return (expression, order)
  in do
    try $ do
      keyword "order"
      keyword "by"
    expressions <- V.fromList <$> commaSep1 order_by_expression
    return expressions

subquery :: CharParser Query
subquery = parens query

function :: CharParser Expression
function = do
  name <- identifier
  argument <- parens expression
  case name of
    "bool_or" -> return $ EAggregate QAggBoolOr argument
    "sum" -> return $ EAggregate QAggSum argument
    _ -> fail $ T.unpack $ "Unknown function " <> name
  

from_clause :: CharParser (Maybe Query)
from_clause =
  let real_from_clause = do
        try $ keyword "from"
        product_query
  in (Just <$> real_from_clause) <|>
     return Nothing

where_clause :: CharParser (Maybe Expression)
where_clause =
  let real_where_clause = do
        try $ keyword "where"
        expression
  in (Just <$> real_where_clause) <|>
     return Nothing

single_query :: CharParser Query
single_query = do
  expressions <- select_clause
  source <- from_clause
  whereClause <- where_clause
  groupBy <- optionMaybe group_by_clause
  orderBy <- optionMaybe order_by_clause
  return $ SingleQuery {
    queryGroupBy = groupBy,
    queryProject = expressions,
    querySource = source,
    queryOrderBy = orderBy,
    queryWhere = whereClause
    }
    
composite_query :: CharParser Query
composite_query =
  let one_or_more = V.fromList <$>
                    sepBy1 single_query union_all
  in do
    composite <- one_or_more
    return $ if V.length composite == 1
             then V.head composite
             else SumQuery QuerySumUnionAll composite

product_query :: CharParser Query
product_query = 
  let one_or_more = V.fromList <$>
                    commaSep1 subquery
  in do
    subqueries <- one_or_more
    return $ if V.length subqueries == 1
             then V.head subqueries
             else ProductQuery { queryFactors = subqueries }

query :: CharParser Query
query = composite_query <?> "Expected a query or union of queries"

select_statement :: CharParser Statement
select_statement = do
  q <- query
  char ';'
  return $ SQuery q

column_type :: CharParser Type
column_type =
  (keyword "int" *> return TInt) <|>
  (keyword "bool" *> return TBool)

table_spec_column :: CharParser Toxic.Column
table_spec_column = do
  name <- identifier
  cType <- column_type
  return Toxic.Column {
    columnName = name,
    columnType = cType
    }

table_spec :: CharParser TableSpec
table_spec = parens $ TableSpec <$> V.fromList <$> commaSep table_spec_column

create_table_statement :: CharParser Statement
create_table_statement = do
  keyword "create"
  keyword "table"
  name <- identifier
  spec <- table_spec
  char ';'
  return $ SCreateTable name spec

statement :: CharParser Statement
statement = select_statement <|> create_table_statement

runQueryParser :: T.Text -> Either ParseError Statement
runQueryParser text = parse statement "runTokenParser" $ T.unpack text

unsafeRunQueryParser :: T.Text -> Statement
unsafeRunQueryParser text = case runQueryParser text of
  Left parseError -> error $ show parseError
  Right statement -> statement
