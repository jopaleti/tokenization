from web3 import Web3
from eth_account import Account
import json

private_key = "53f79ba46063a9ceef03f510f9f9e3832269cdd46f7774a10ad0eb79b46f26c5"
password = "tobi1234#"

acct = Account.from_key(private_key)
keystore = acct.encrypt(password)

with open("/Users/macchine/.foundry/keystores/defaultKey", "w") as f:
    json.dump(keystore, f)
