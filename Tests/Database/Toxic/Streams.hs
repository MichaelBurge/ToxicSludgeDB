{-# LANGUAGE OverloadedStrings #-}

module Tests.Database.Toxic.Streams (streamsTests) where

import qualified Data.Vector as V

import Database.Toxic.Aggregates
import Database.Toxic.Streams
import Database.Toxic.Types

import Test.Framework
import Test.Framework.Providers.HUnit (testCase)
import Test.Framework.Providers.QuickCheck2 (testProperty)
import Test.HUnit
import Test.QuickCheck

test_cross_join_records :: Assertion
test_cross_join_records =
  let record1 = Record $ V.fromList [ VBool True, VBool False ]
      record2 = Record $ V.fromList [ VBool False, VBool True ]
      expectedRecord = Record $ V.fromList [
        VBool True, VBool False,
        VBool False, VBool True
        ]
      actualRecord = crossJoinRecords $ V.fromList [ record1, record2 ]
  in assertEqual "" expectedRecord actualRecord

test_union_all :: Assertion
test_union_all =
  let column = Column { columnName = "x", columnType = TBool }
      stream1 = singleton_stream column $ VBool True
      stream2 = singleton_stream column $ VBool True
      expectedStream = single_column_stream column [ VBool True, VBool True ]
      actualStream = sumStreams QuerySumUnionAll $ V.fromList [ stream1, stream2 ]
  in assertEqual "" expectedStream actualStream

test_cross_join :: Assertion
test_cross_join =
  let stream1 = Stream {
        streamHeader = V.singleton $ Column { columnName = "x", columnType = TBool },
        streamRecords = map (Record . V.singleton) [ VBool True, VBool False, VBool True ]
        }
      stream2 = Stream {
        streamHeader = V.singleton $ Column { columnName = "y", columnType = TBool },
        streamRecords = map (Record . V.singleton) [ VBool False, VBool True ]
        }
      expectedStream = Stream {
        streamHeader = V.fromList [
           Column { columnName = "$0.x", columnType = TBool },
           Column { columnName = "$1.y", columnType = TBool }
           ],
        streamRecords = map (Record . V.fromList) [
          [ VBool True, VBool False],
          [ VBool True, VBool True ],
          
          [ VBool False, VBool False ],
          [ VBool False, VBool True ],
          
          [ VBool True, VBool False ],
          [ VBool True, VBool True ]
          ]
        }
      actualStream = crossJoinStreams $ V.fromList [ stream1, stream2 ]
  in assertEqual "" expectedStream actualStream

test_aggregate :: Assertion
test_aggregate =
  let column = Column { columnName = "x", columnType = TBool }
      stream = single_column_stream column $ [ VBool False, VBool True ]
      expectedRecord = Record $ V.singleton $ VBool True
      actualRecord = summarize_stream stream $ V.fromList [ bool_or ]
  in assertEqual "" expectedRecord actualRecord

streamsTests :: Test.Framework.Test
streamsTests =
  testGroup "Streams" [
    testCase "Union all" test_union_all,
    testCase "Cross join(record)" test_cross_join_records,
    testCase "Cross join" test_cross_join,
    testCase "Aggregate" test_aggregate
    ]