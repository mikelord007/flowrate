import FungibleToken


access(all) contract FlowRate {
    access(all) var borrowLimitPerBucket: UFix64 // Max Percentage of Debt a bucket can have, over which assets will be liquidated 
    access(all) let supplyTokensLimit : {String : UFix64} // Type Identifier of Token : Hard Upper limit on amount of tokens
    access(all) let borrowTokensLimit : {String : UFix64} // Type Identifier of Token : Percentage of max borrowable from pool
    access(all) let suppliedTokens: {UInt64: {String: UFix64}} // UUID of liquidity Bucket : {Type Identifier of Token : Amount of supply}
    access(all) let borrowedTokens: {UInt64: {String: UFix64}} // UUID of liquidity Bucket : {Type Identifier of Token : Amount of debt}
    
    access(all) let tokenVaults: @{String: FungibleToken.Vault} // Type Identifier of Token : Vault

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

            assert(!FlowRate.checkIfBucketIsUnderCollateralized(bucket: self.uuid), message : "Undercollateralized UnSupply")
        }

        access(contract) fun borrowTokens(tokenIdentifier: String, amount: UFix64) {
            FlowRate.borrowedTokens[self.uuid] = {tokenIdentifier: (FlowRate.borrowedTokens[self.uuid]![tokenIdentifier] != nil ? FlowRate.borrowedTokens[self.uuid]![tokenIdentifier]! : 0.0) + amount}

            assert(!FlowRate.checkIfBucketIsUnderCollateralized(bucket: self.uuid), message : "Undercollateralized Borrow")
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
        //todo: add functions to modify the borrowLimitPerBucket, supplyTokensLimit, borrowTokensLimit
    }

    access(all) fun supply(supplyTokenVault: @FungibleToken.Vault, existingLiquidityBucket: @liquidityBucket?, bucketList: &bucketList): @liquidityBucket {
        pre {
            self.supplyTokensLimit.containsKey(supplyTokenVault.getType().identifier): "Can't supply this token"
            supplyTokenVault.balance <= self.supplyTokensLimit[supplyTokenVault.getType().identifier]! : "Amount greater than limit"
            supplyTokenVault.balance >= 0.0 : "Are you joking bruv"
        }
        post {
            //todo: check if supply exceeds limit
        }

        let tokenVaultTypeIdentifier = supplyTokenVault.getType().identifier
        let supplyAmount = supplyTokenVault.balance

        self.depositToVault(tokenIdentifier: tokenVaultTypeIdentifier, supplyVault: <- supplyTokenVault)

        if(existingLiquidityBucket != nil) {
            let returnBucket <- existingLiquidityBucket!
            returnBucket.supplyTokens(tokenIdentifier: tokenVaultTypeIdentifier, amount: supplyAmount)
            return <- returnBucket
        }
        else {
            destroy existingLiquidityBucket
        }

        let newBucket <- create liquidityBucket()
        newBucket.supplyTokens(tokenIdentifier: tokenVaultTypeIdentifier, amount: supplyAmount)
        bucketList.addBucketToList(bucketID: newBucket.uuid)
        return <- newBucket
    }

    access(all) fun unsupply(bucket: &liquidityBucket, tokenIdentifier: String, amount: UFix64): @FungibleToken.Vault {
        pre {
            self.supplyTokensLimit.containsKey(tokenIdentifier): "Unsupported tokenIdentifier"
            amount >= 0.0 : "Are you joking bruv"
        }

        bucket.unSupplyTokens(tokenIdentifier: tokenIdentifier, amount: amount) // checks if un supplying doesn't leave bucket undercollateralized
        return <- self.withdrawFromVault(tokenIdentifier: tokenIdentifier, amount: amount)
    }

    access(all) fun checkIfBucketIsUnderCollateralized(bucket: UInt64) : Bool {
        var totalSupply = 0.0
        var totalDebt = 0.0

        self.suppliedTokens[bucket]!.forEachKey(fun (key: String): Bool {
            totalSupply = self.fetchPriceFromOracle(type: key) * self.suppliedTokens[bucket]![key]! + totalSupply
            return true
        })

        self.borrowedTokens[bucket]!.forEachKey(fun (key: String): Bool {
            totalDebt = self.fetchPriceFromOracle(type: key) * self.borrowedTokens[bucket]![key]! + totalDebt
            return true
        })

        if(totalSupply == 0.0 && totalDebt == 0.0 ) {
            return false
        }
        
        return (totalDebt * 100.0) / totalSupply >= self.borrowLimitPerBucket
    }

    access(all) fun fetchPriceFromOracle(type: String): UFix64 {
        return 1.0 // keeping it simple for this hack
    }

    access(contract) fun depositToVault(tokenIdentifier: String, supplyVault: @FungibleToken.Vault) {
        var tempVault: @FungibleToken.Vault? <- nil
        tempVault <-> self.tokenVaults[tokenIdentifier]
        var finalVault <- tempVault!
        finalVault.deposit(from: <- supplyVault)
        let dumpVault <- self.tokenVaults[tokenIdentifier] <- finalVault
        
        destroy dumpVault
    }

    access(contract) fun withdrawFromVault(tokenIdentifier: String, amount: UFix64): @FungibleToken.Vault {
        var tempVault: @FungibleToken.Vault? <- nil
        tempVault <-> self.tokenVaults[tokenIdentifier]
        var finalVault <- tempVault!
        let returnVault <- finalVault.withdraw(amount: amount)
        let dumpVault <- self.tokenVaults[tokenIdentifier] <- finalVault
        
        destroy dumpVault
        
        return <- returnVault
    }

    init() {
        self.borrowLimitPerBucket = 0.0
        self.supplyTokensLimit = {}
        self.borrowTokensLimit = {}
        self.suppliedTokens = {}
        self.borrowedTokens = {}
        self.tokenVaults <- {}
    }
}