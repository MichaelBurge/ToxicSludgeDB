{-# LANGUAGE OverloadedStrings #-}

module Database.Toxic.Query.Interpreter where

import Database.Toxic.Query.AST
import Database.Toxic.Types

import Control.Applicative
import qualified Data.Text as T

import qualified Data.Vector as V

data Environment = Environment { }

data BindingContext = BindingContext { }

nullEnvironment :: Environment
nullEnvironment = error "TODO: Implement nullEnvironment"

nullContext :: BindingContext
nullContext = error "TODO: Implement nullContext"

literalType :: Literal -> Type
literalType literal = case literal of
  LBool _ -> TBool

expressionType :: Expression -> Type
expressionType expression = case expression of
  ELiteral x -> literalType x
  ERename x _ -> expressionType x

expressionName :: Expression -> T.Text
expressionName expression = case expression of
  ELiteral _ -> "literal"
  ERename _ x -> x

expressionColumn :: Expression -> Column
expressionColumn expression = Column {
  columnType = expressionType expression,
  columnName = expressionName expression
  }

queryColumns :: Query -> ArrayOf Column
queryColumns query = V.map expressionColumn (queryProject query)

evaluateLiteral :: Literal -> Value
evaluateLiteral literal = case literal of
  LBool x -> VBool x

-- TODO: This is only for row-wise expressions, not aggregates.
evaluateOneExpression :: BindingContext -> Expression -> Value
evaluateOneExpression context expression = case expression of
  ELiteral literal -> evaluateLiteral literal
  ERename x _ -> evaluateOneExpression context x

evaluateExpressions :: ArrayOf Expression -> BindingContext -> Record
evaluateExpressions expressions context = 
  Record $ V.map (evaluateOneExpression context) expressions

resolveQueryBindings :: Environment -> Query -> IO (SetOf BindingContext)
resolveQueryBindings environment query = return [nullContext]

evaluateQuery :: Environment -> Query -> IO Stream
evaluateQuery environment query =
  let streamHeader     = queryColumns query
      queryExpressions = queryProject query :: ArrayOf Expression
  in do
    bindingContexts <- resolveQueryBindings environment query
    let streamRecords = map (evaluateExpressions queryExpressions) bindingContexts
    return Stream {
      streamHeader = streamHeader,
      streamRecords = streamRecords
      }
     
execute :: Environment -> Statement -> IO Stream
execute environment statement = case statement of
  SQuery query -> evaluateQuery environment query

singleton_stream :: Column -> Value -> Stream
singleton_stream column value =
  let header = V.singleton column
      records = [ Record $ V.singleton value ]
  in Stream { streamHeader = header, streamRecords = records }
