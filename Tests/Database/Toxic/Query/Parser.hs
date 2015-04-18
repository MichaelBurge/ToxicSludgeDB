module Tests.Database.Toxic.Query.Parser (parserTests) where

import Database.Toxic.Types
import Database.Toxic.Query.AST
import Database.Toxic.Query.Parser
import Database.Toxic.Query.Tokenizer

import Test.Framework
import Test.Framework.Providers.HUnit (testCase)
import Test.Framework.Providers.QuickCheck2 (testProperty)
import Test.HUnit
import Test.QuickCheck

import qualified Data.Vector as V

test_booleanSelect :: Assertion
test_booleanSelect = do
  let tokens = [ TkSelect, TkTrue, TkStatementEnd ]
  let parseResult = runTokenParser tokens
  let literalTrue = ELiteral $ LBool True
  let expectedStatement = SQuery $ Query {
        queryProject = V.singleton literalTrue
        }
  case parseResult of
    Left parseError -> error $ show parseError
    Right actualStatement ->
      assertEqual "Boolean select" expectedStatement actualStatement
  
parserTests :: Test.Framework.Test
parserTests =
  testGroup "Parser" [
    testCase "Boolean select" test_booleanSelect
    ]
  
