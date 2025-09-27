import "FungibleToken"
import templateToken from "../contracts/templateToken.cdc"

transaction(amount: UFix64) {
    prepare(account: auth(BorrowValue, SaveValue) &Account) {

        var minter: &templateToken.Minter? = account.storage.borrow<&templateToken.Minter>(from: templateToken.AdminStoragePath)
            ?? panic("Could not borrow reference to the token minter")

        let newVault <- minter?.mintTokens(amount: amount)

        let vaultRef= account.storage.borrow<auth(FungibleToken.Withdraw) &templateToken.Vault>(
               from: templateToken.VaultStoragePath)
            ?? panic("Vault not found")

        vaultRef.deposit(from: <- newVault as! @{FungibleToken.Vault})
    }
}