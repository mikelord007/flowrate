import "FungibleToken"
import templateToken from "../contracts/templateToken.cdc"

access(all)
fun main(address: Address): String {
    let account = getAccount(address)

    let accountReceiverRef= account.capabilities.get<&{FungibleToken.Balance}>(templateToken.VaultPublicPath)
                            .borrow()
            ?? panic("Vault not found")

    return("Balance for "
        .concat(address.toString())
        .concat(": ").concat(accountReceiverRef.balance.toString())
        )
}
