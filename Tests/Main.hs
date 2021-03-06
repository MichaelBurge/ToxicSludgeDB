import Test.Framework (defaultMain)

import Tests.Database.Toxic.Query.Interpreter (interpreterTests)
import Tests.Database.Toxic.Query.Parser (parserTests)
import Tests.Database.Toxic.Streams (streamsTests)
import Tests.Database.Toxic.TSql.Protocol (protocolTests)
import Tests.Database.Toxic.TSql.ProtocolHelper (protocolHelperTests)

import Tests.ExampleQueries (exampleQueriesTests)

main = defaultMain tests
tests =
  [
    interpreterTests,
    parserTests,
    streamsTests,
    exampleQueriesTests,
    protocolTests,
    protocolHelperTests
  ]
