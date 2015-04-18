module Database.Toxic.Query.Tokenizer where

import Control.Applicative ((<$>), (*>), (<*>))
import qualified Data.Text as T
import Text.Parsec

type CharParser a = Parsec String () a

data SourcePosition = SourcePosition { line, column :: Int } deriving (Eq, Show)

data Token =
     TkSelect
   | TkTrue
   | TkFalse
   | TkStatementEnd
   | TkRename
   | TkIdentifier T.Text
   deriving (Eq, Show)

lexStatementEnd :: CharParser Token
lexStatementEnd = char ';' *> return TkStatementEnd

lexKeyword :: CharParser Token
lexKeyword =
  let tryKeyword keyword token = string keyword *> spaces *> return token
  in     tryKeyword "select" TkSelect
     <|> tryKeyword "true" TkTrue
     <|> tryKeyword "false" TkFalse
     <|> tryKeyword "as" TkRename

lexIdentifier :: CharParser Token
lexIdentifier =
  let chars = (:) <$> letter <*> many alphaNum
  in TkIdentifier <$> T.pack <$> chars

lexOneToken :: CharParser Token
lexOneToken =
        lexStatementEnd
    <|> lexKeyword
    <|> lexIdentifier

lexer :: CharParser [ Token ]
lexer = many lexOneToken

runTokenLexer :: T.Text -> Either ParseError [Token]
runTokenLexer source = parse lexer "lex" $ T.unpack source

unsafeRunTokenLexer :: T.Text -> [ Token ]
unsafeRunTokenLexer source = case runTokenLexer source of
  Left parseError -> error $ show parseError
  Right tokens -> tokens