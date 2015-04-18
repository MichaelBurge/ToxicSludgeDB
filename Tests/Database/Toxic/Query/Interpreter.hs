{-# LANGUAGE OverloadedStrings #-}

module Tests.Database.Toxic.Query.Interpreter (interpreterTests) where

import qualified Data.Vector as V

import Database.Toxic.Types
import Database.Toxic.Query.AST
import Database.Toxic.Query.Interpreter

import Test.Framework
import Test.Framework.Providers.HUnit (testCase)
import Test.Framework.Providers.QuickCheck2 (testProperty)
import Test.HUnit
import Test.QuickCheck

test_booleanSelect :: Assertion
test_booleanSelect = do
  let expression = ELiteral $ LBool True
  let query = Query { queryProject = V.singleton expression }
  let statement = SQuery query
  actualStream <- execute nullEnvironment statement
  let expectedHeader = V.singleton $ Column {
        columnName = "literal",
        columnType = TBool
        }
  let expectedStream = Stream {
        streamHeader = expectedHeader,
        streamRecords = [ Record $ V.singleton $ VBool True ]
        }
  assertEqual "Boolean select" expectedStream actualStream

interpreterTests :: Test.Framework.Test
interpreterTests =
  testGroup "Interpreter" [
    testCase "Boolean select" test_booleanSelect
    ]
