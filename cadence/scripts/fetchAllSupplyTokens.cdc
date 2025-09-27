import FlowRate from "../contracts/flowrate.cdc"

access(all) fun main(): [String] {
    
    let supplyTokensLimit = FlowRate.supplyTokensLimit
    let supplyTokens: [String] = []
    
    supplyTokensLimit.forEachKey(fun (key: String): Bool {
        supplyTokens.append(key)
        return true
    })

    return supplyTokens
}