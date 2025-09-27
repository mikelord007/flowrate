import FlowRate from "../contracts/flowrate.cdc"

transaction() {
    prepare(account: auth(BorrowValue, SaveValue) &Account) {

        var bucketList: &FlowRate.bucketList? = account.storage.borrow<&FlowRate.bucketList>(from: FlowRate.bucketListStoragePath)
        
        // var receiverRef = account.capabilities.borrow<&FlowRate.bucketList>(FlowRate.bucketListPublicPath)

        let newBucket <- FlowRate.createEmptyBucket(bucketList: bucketList!)
        let bucketUUID = newBucket.uuid

        account.storage.save(<- newBucket, to: StoragePath(identifier: FlowRate.liquidityBucketStorageTemplate.concat(bucketUUID.toString()))!)
    }
}