import FungibleToken


access(all) contract FlowRate {
    access(all) var borrowLimitPerBucket: UFix64 // Max Percentage of Debt a bucket can have, over which assets will be liquidated 
    access(all) let supplyTokensLimit : {String : UFix64} // Type Identifier of Token : Hard Upper limit on amount of tokens
    access(all) let borrowTokensLimit : {String : UFix64} // Type Identifier of Token : Percentage of max borrowable from pool
    access(all) let suppliedTokens: {UInt64: {String: UFix64}} // UUID of liquidity Bucket : {Type Identifier of Token : Amount of supply}
    access(all) let borrowedTokens: {UInt64: {String: UFix64}} // UUID of liquidity Bucket : {Type Identifier of Token : Amount of debt}

    access(all) resource bucketList {
        access(all) let holdingBucketsList: [UInt64]

        access(contract) fun addBucketToList(bucketID: UInt64) {
            self.holdingBucketsList.append(bucketID)
        }

        access(contract) fun removeBucketToList(bucketID: UInt64) {
            self.holdingBucketsList.remove(at: self.holdingBucketsList.firstIndex(of: bucketID)!)
        }

        init() {
            self.holdingBucketsList = []
        }
    }

    access(all) resource liquidityBucket {
        access(contract) fun supplyTokens(tokenIdentifier: String, amount: UFix64) {
            FlowRate.suppliedTokens[self.uuid] = {tokenIdentifier: (FlowRate.suppliedTokens[self.uuid]![tokenIdentifier] != nil ? FlowRate.suppliedTokens[self.uuid]![tokenIdentifier]! : 0.0) + amount} 
        }

        access(contract) fun unSupplyTokens(tokenIdentifier: String, amount: UFix64) {
            FlowRate.suppliedTokens[self.uuid] = {tokenIdentifier: (FlowRate.suppliedTokens[self.uuid]![tokenIdentifier] != nil ? FlowRate.suppliedTokens[self.uuid]![tokenIdentifier]! : 0.0) - amount}

            //todo: check if undercollateralized
        }

        access(contract) fun borrowTokens(tokenIdentifier: String, amount: UFix64) {
            FlowRate.borrowedTokens[self.uuid] = {tokenIdentifier: (FlowRate.borrowedTokens[self.uuid]![tokenIdentifier] != nil ? FlowRate.borrowedTokens[self.uuid]![tokenIdentifier]! : 0.0) + amount}

            //todo: check if undercollateralized
        }

        access(contract) fun repayTokens(tokenIdentifier: String, amount: UFix64) {
            FlowRate.borrowedTokens[self.uuid] = {tokenIdentifier: (FlowRate.borrowedTokens[self.uuid]![tokenIdentifier] != nil ? FlowRate.borrowedTokens[self.uuid]![tokenIdentifier]! : 0.0) - amount}
        }
        
        init() {
            FlowRate.suppliedTokens[self.uuid] = {}
            FlowRate.borrowedTokens[self.uuid] = {}
        }

    }

    access(all) resource Administrator {

    }

    init() {
        self.borrowLimitPerBucket = 0.0
        self.supplyTokensLimit = {}
        self.borrowTokensLimit = {}
        self.suppliedTokens = {}
        self.borrowedTokens = {}
    }
}