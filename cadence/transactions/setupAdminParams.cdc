import FungibleToken from "FungibleToken"
import FlowRate from "../contracts/flowrate.cdc"

transaction(
    allowedTokens: [String]
) {
   prepare(adminAccount: auth(BorrowValue, SaveValue, IssueStorageCapabilityController, PublishCapability) &Account) {

        let bucketList <- FlowRate.createBucketList()
        adminAccount.storage.save(<- bucketList, to: FlowRate.bucketListStoragePath)

        let capability = adminAccount.capabilities.storage.issue<&FlowRate.bucketList>(FlowRate.bucketListStoragePath)

        let bucketListCapability = adminAccount.capabilities.storage.issue<&FlowRate.bucketList>(FlowRate.bucketListStoragePath)

        adminAccount.capabilities.publish(bucketListCapability, at: FlowRate.bucketListPublicPath)

        let bucketListRef = adminAccount.capabilities.borrow<&FlowRate.bucketList>(FlowRate.bucketListPublicPath)

        let adminResource = adminAccount.storage.borrow<&FlowRate.Administrator>(from: FlowRate.AdminResourceStoragePath)

        adminResource!.modifyBorrowLimitPerBucket(newLimit: 80.00)

        var i = 0
        
        while i < allowedTokens.length {

            adminResource!.modifySupplyTokensLimit(supplyToken: allowedTokens[i], limit: 1000000000.0)
            adminResource!.modifyBorrowTokensLimit(borrowToken: allowedTokens[i], limit: 70.0)
            
            i = i + 1
        }
    }
}