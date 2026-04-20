


 forge verify-bytecode 0xE638DaEafa7E76D0D97d42508e8daA801e2431A1 src/hooks/MetaHooks.sol:MetaHooks \
    --constructor-args $(cast abi-encode "constructor(address,address,address)" 0xD1573de52fFF44dd92D275e20Fdab0296CCFF141 0x11BCB7109a60F76d98Cb67dC6e16bD39A622dE1D 0x11BCB7109a60F76d98Cb67dC6e16bD39A622dE1D) --etherscan-api-key $ETHERSCAN_API_KEY --rpc-url $RPC_URL --compiler-version 0.8.24 --num-of-optimizations 200 --evm-version cancun

forge verify-contract 0x0951Da4f9259b272D4Dc9F78251169355f10D6aA lib/yieldnest-vault/src/hooks/FeeHooks.sol:FeeHooks --constructor-args $(cast abi-encode "constructor(address,address,uint256,address,(bool,bool,bool,bool,bool,bool,bool,bool,bool,bool))" 0xE638DaEafa7E76D0D97d42508e8daA801e2431A1 0xfcad670592a3b24869C0b51a6c6FDED4F95D6975 0 0xC92Dd1837EBcb0365eB0a8795f9c8E474f8B6183 "(false,false,false,false,false,false,false,false,false,true)") --etherscan-api-key $ETHERSCAN_API_KEY --rpc-url $RPC_URL --compiler-version 0.8.24 --num-of-optimizations 200 --evm-version cancun


forge verify-contract 0x6ae02e8F07aA8E0e39857f99ECd4E5152B534a84 src/hooks/ProcessAccountingGuardHook.sol:ProcessAccountingGuardHook --constructor-args $(cast abi-encode "constructor(address,address,uint256,uint256,uint256,uint256)" 0xE638DaEafa7E76D0D97d42508e8daA801e2431A1 0xfcad670592a3b24869C0b51a6c6FDED4F95D6975 1000000000000000 2000000000000000 0 0) --etherscan-api-key $ETHERSCAN_API_KEY --rpc-url $RPC_URL --compiler-version 0.8.24 --num-of-optimizations 200 --evm-version cancun