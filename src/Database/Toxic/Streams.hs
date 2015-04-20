module Database.Toxic.Streams where

import Database.Toxic.Types

import Data.List (foldl')
import qualified Data.Text as T
import qualified Data.Vector as V
import qualified Text.Show.Text as T

nullStream :: Stream
nullStream = Stream {
  streamHeader = V.empty,
  streamRecords = []
  }

-- | Summing two streams acts on the set of records but does not change the header. Examples include union, intersect, except operations.
-- | As a result, all streams must match in size and type.
-- TODO: Add asserts for size and type
sumStreams :: QuerySumOperation -> ArrayOf Stream -> Stream
sumStreams op streams =
  if V.null streams
  then nullStream
  else
    let header = streamHeader $ V.head streams
        records = case op of
          QuerySumUnionAll -> unionAllRecords $
                              V.map streamRecords streams
    in Stream {
      streamHeader = header,
      streamRecords = records
      }

-- | Creates a new record by appending all the columns from each record
crossJoinRecords :: ArrayOf Record -> Record
crossJoinRecords records =
  let extractValues (Record values) = values
  in Record $ V.concatMap extractValues records

-- | Creates a new stream with a header that combines the headers of the constituents.
-- | Variable x in stream n assigned the name '$n.x'.
crossJoinStreams :: ArrayOf Stream -> Stream
crossJoinStreams streams =
  let getNewName idx name = T.cons '$' $
                            T.append (T.show idx) $
                            T.cons '.' $
                            name
      getNewNames idx names = V.map (getNewName idx) names :: ArrayOf T.Text
      getNewColumns idx columns =
        let names = V.map columnName columns
            newNames = getNewNames idx names
        in V.zipWith (\column newName -> Column {
                     columnName = newName,
                     columnType = columnType column
                     }) columns newNames :: ArrayOf Column
      header = V.concatMap id $
               V.imap getNewColumns $
               V.map streamHeader streams :: ArrayOf Column
      records =
        let recordSets = sequence $
                         V.toList $
                         V.map streamRecords
                         streams :: [[ Record ]]
            combinedRecords = map (crossJoinRecords . V.fromList) recordSets :: [ Record ]
        in combinedRecords
  in Stream {
    streamHeader = header,
    streamRecords = records
    }

-- | Multiplying two streams creates a new stream with the header being a union of the constituent streams' headers, and the records being a function of the
-- | cartesian product. Examples include SQL join.
multiplyStreams :: QueryProductOperation -> ArrayOf Stream -> Stream
multiplyStreams op streams =
  case op of
    QueryProductCrossJoin -> crossJoinStreams streams


unionAllRecords :: ArrayOf (SetOf Record) -> SetOf Record
unionAllRecords recordss = concat $ V.toList recordss

summarize_stream :: Stream -> ArrayOf AggregateFunction -> Record
summarize_stream stream aggregates =
  let initialStates = V.map aggregateInitialize aggregates :: ArrayOf AggregateState
      accumulateValue states values = V.zipWith3 aggregateAccumulate aggregates values states :: ArrayOf AggregateState
      unwrapRecord (Record x) = x :: ArrayOf Value
      unwrappedRecords = map unwrapRecord $
                         streamRecords stream :: SetOf (ArrayOf Value)
  in Record $
     V.zipWith aggregateFinalize aggregates $
     foldl' accumulateValue initialStates unwrappedRecords


singleton_stream :: Column -> Value -> Stream
singleton_stream column value =
  let header = V.singleton column
      records = [ Record $ V.singleton value ]
  in Stream { streamHeader = header, streamRecords = records }

single_column_stream :: Column -> [ Value ] -> Stream
single_column_stream column values =
  let header = V.singleton column
      records = map (Record . V.singleton) values
  in Stream { streamHeader = header, streamRecords = records }