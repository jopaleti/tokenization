const fs = require("fs")
const { Location, ReturnType, CodeLanguage } = require("@chainlink/functions-toolkit")
const { secretsLocation } = require("./alpacaMintConfig")

// Configure the request by setting the fields below
const requestConfig = {
    // String containing the source code to be executed
    source: fs.readFileSync("./functions/sources/sellTslaAndSendUsdc.js").toString(),
    // Location of source code (only Inline is currently supported)
    codeLocation: Location.Inline,
      // Optional. Secrets can be accessed within the source code with `secrets.varName` (ie: secrets.apiKey). The secrets object can only contain string values.
    secret: {
        alpacaKey: process.env.ALPACA_API_KEY ?? "",
        alpacaSecret: process.env.ALPACA_SECRET_KEY ?? ""
    },
    secretsLocation: Location.DONHosted,
    args: ["1", "1"],
    CodeLanguage: CodeLanguage.JavaScript,
    expectedReturnType: ReturnType.uint256,
}

module.exports = requestConfig;