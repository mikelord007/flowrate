import "FungibleToken"


access(all) contract FlowRate {
    access(all) var borrowLimitPerBucket: UFix64 // Max Percentage of Debt a bucket can have, over which assets will be liquidated 
    access(all) let supplyTokensLimit : {String : UFix64} // Type Identifier of Token : Hard Upper limit on amount of tokens
    access(all) let borrowTokensLimit : {String : UFix64} // Type Identifier of Token : Percentage of max borrowable from pool
    access(all) let suppliedTokens: {UInt64: {String: UFix64}} // UUID of liquidity Bucket : {Type Identifier of Token : Amount of supply}
    access(all) let borrowedTokens: {UInt64: {String: UFix64}} // UUID of liquidity Bucket : {Type Identifier of Token : Amount of debt}
    
    access(all) var tokenVaults: @{String: {FungibleToken.Vault}} // Type Identifier of Token : Vault

    access(all) let AdminResourceStoragePath: StoragePath
    access(all) let bucketListStoragePath: StoragePath
    access(all) let bucketListPublicPath: PublicPath
    access(all) let liquidityBucketStorageTemplate: String

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
        access(all) fun modifyBorrowLimitPerBucket(newLimit : UFix64) {
            FlowRate.borrowLimitPerBucket = newLimit
        }

        access(all) fun modifySupplyTokensLimit(supplyToken: String, limit: UFix64) {
            FlowRate.supplyTokensLimit[supplyToken] = limit
        }

        access(all) fun modifyBorrowTokensLimit(borrowToken: String, limit: UFix64) {
            FlowRate.borrowTokensLimit[borrowToken] = limit
        }

        access(all) fun initTokenVault(tokenIdentifier: String, vault: @{FungibleToken.Vault}): @{FungibleToken.Vault}? {
            if(FlowRate.tokenVaults[tokenIdentifier] == nil ) {
                FlowRate.tokenVaults[tokenIdentifier] <-! vault
                return nil
            }

            return <- vault
        }

        access(all) fun liquidateUnderCollateralizedBuckets() {
            FlowRate.borrowedTokens.forEachKey(fun (key: UInt64): Bool {
                let underCollateralized = FlowRate.checkIfBucketIsUnderCollateralized(bucket: key)

                if(underCollateralized) {
                    FlowRate.suppliedTokens.insert(key: key, {})
                    FlowRate.borrowedTokens.insert(key: key, {})
                }

                return true
            })
        }
    }

    access(all) fun supply(supplyTokenVault: @{FungibleToken.Vault}, existingLiquidityBucket: @liquidityBucket?, bucketList: &bucketList): @liquidityBucket {
        pre {
            self.supplyTokensLimit.containsKey(supplyTokenVault.getType().identifier): "Can't supply this token"
            supplyTokenVault.balance <= self.supplyTokensLimit[supplyTokenVault.getType().identifier]! : "Amount greater than limit"
            supplyTokenVault.balance >= 0.0 : "can't supply 0 tokens lol"
        }
        post {
            self.supplyTokensLimit[tokenVaultTypeIdentifier]! >= totalSuppliedAfter : "supply exceeds limit"
        }

        let tokenVaultTypeIdentifier = supplyTokenVault.getType().identifier
        let supplyAmount = supplyTokenVault.balance
        let totalSuppliedAfter = self.totalSupplied(tokenIdentifier: tokenVaultTypeIdentifier) + supplyAmount


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

    access(all) fun unsupply(bucket: &liquidityBucket, tokenIdentifier: String, amount: UFix64): @{FungibleToken.Vault} {
        pre {
            self.supplyTokensLimit.containsKey(tokenIdentifier): "Unsupported tokenIdentifier"
            amount >= 0.0 : "can't unsupply 0 tokens lol"
        }

        bucket.unSupplyTokens(tokenIdentifier: tokenIdentifier, amount: amount) // checks if un supplying doesn't leave bucket undercollateralized
        return <- self.withdrawFromVault(tokenIdentifier: tokenIdentifier, amount: amount)
    }

    access(all) fun borrow(bucket: &liquidityBucket, tokenIdentifier: String, amount: UFix64): @{FungibleToken.Vault} {
        pre {
            self.borrowTokensLimit.containsKey(tokenIdentifier): "Unsupported tokenIdentifier"
            amount >= 0.0 : "can't borrow 0 tokens lol"
        }

        bucket.borrowTokens(tokenIdentifier: tokenIdentifier, amount: amount) // checks if borrowing doesn't leave bucket undercollateralized

        return <- self.withdrawFromVault(tokenIdentifier: tokenIdentifier, amount: amount)

    }

    access(all) fun repay(bucket: &liquidityBucket, tokenVault: @{FungibleToken.Vault}) {
        pre {
            self.borrowTokensLimit.containsKey(tokenVault.getType().identifier): "Unsupported tokenIdentifier"
            tokenVault.balance >= 0.0 : "can't repay 0 tokens lol"
        }

        let tokenTypeIdentifier = tokenVault.getType().identifier
        let tokenAmount = tokenVault.balance

        self.depositToVault(tokenIdentifier: tokenTypeIdentifier, supplyVault: <- tokenVault)
        bucket.repayTokens(tokenIdentifier: tokenTypeIdentifier, amount: tokenAmount)
    }

    access(all) fun createEmptyBucket(bucketList: &bucketList): @liquidityBucket {
        let bucket <- create liquidityBucket()
        bucketList.addBucketToList(bucketID: bucket.uuid)
        return <- bucket
    }

    access(all) fun createBucketList(): @bucketList {
        return <- create bucketList()
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

    access(all) fun totalSupplied(tokenIdentifier: String): UFix64 {
        var totalSupplied = 0.0

        FlowRate.suppliedTokens.forEachKey(fun (bucket: UInt64): Bool {
            
            if(FlowRate.suppliedTokens[bucket]![tokenIdentifier] != nil) {
                totalSupplied = totalSupplied + self.fetchPriceFromOracle(type: tokenIdentifier) * FlowRate.suppliedTokens[bucket]![tokenIdentifier]!
            }

            return true
        })

        return totalSupplied 
    }

    access(all) fun totalBorrowed(tokenIdentifier: String): UFix64 {
        var totalBorrowed = 0.0

        FlowRate.borrowedTokens.forEachKey(fun (bucket: UInt64): Bool {
            
            if(FlowRate.borrowedTokens[bucket]![tokenIdentifier] != nil) {
                totalBorrowed = totalBorrowed + self.fetchPriceFromOracle(type: tokenIdentifier) * FlowRate.borrowedTokens[bucket]![tokenIdentifier]!
            }
            
            return true
        })

        return totalBorrowed
    }

    access(contract) fun depositToVault(tokenIdentifier: String, supplyVault: @{FungibleToken.Vault}) {
        var tempVault: @{FungibleToken.Vault}? <- nil
        tempVault <-> self.tokenVaults[tokenIdentifier]
        var finalVault <- tempVault!
        finalVault.deposit(from: <- supplyVault)
        let dumpVault <- self.tokenVaults[tokenIdentifier] <- finalVault
        
        destroy dumpVault
    }

    access(contract) fun withdrawFromVault(tokenIdentifier: String, amount: UFix64): @{FungibleToken.Vault} {
        var tempVault: @{FungibleToken.Vault}? <- nil
        tempVault <-> self.tokenVaults[tokenIdentifier]
        var finalVault <- tempVault!
        let returnVault <- finalVault.withdraw(amount: amount)
        let dumpVault <- self.tokenVaults[tokenIdentifier] <- finalVault
        
        destroy dumpVault
        
        return <- returnVault
    }

    init() {
        self.borrowLimitPerBucket = 80.00
        self.supplyTokensLimit = {}
        self.borrowTokensLimit = {}
        self.suppliedTokens = {}
        self.borrowedTokens = {}
        self.tokenVaults <- {}
        self.AdminResourceStoragePath = /storage/adminResourcePath
        self.bucketListStoragePath = /storage/bucketList
        self.bucketListPublicPath = /public/bucketList
        self.liquidityBucketStorageTemplate = "liquidityBucket" // + add id at end

        self.account.storage.save(<- create Administrator(), to: self.AdminResourceStoragePath)
    }
}