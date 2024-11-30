# 🤖 Brianker-Contracts

This repository contains the V4-Hook contracts to 

## 📋 Contract Description

The BriankerHook acts both as a factory to deploy ERC20 and as a way to lock trades up to its official trade opening.
Through `launchTokenWithTimeLock()` our bot can initialize a token and launch a pool within a single transaction, passing the parameters extracted w/ Brian Apis.

The hook itself deploy a fixed supply of 1e24, initialize and adds the liquidity at once via multicall using 100% of the supply. Since the hook itself will be the owner of the full supply in order to prevent dumps by the creator, the pool has all the liquidity it needs, thus it will be the only LP at that time.
This makes the pool more like a vending machine on a curve at first.

In `beforeSwap` a check is made against the `PoolKey` locker to determine wheter or not a pair is tradable.



### **Test the hook v4 Hooks 🦄**

## Set up
```
forge install
```
## Commands

Build via:

```bash
forge build 
```
Test via:

```bash
forge test 
```
Use scripts via:

```bash
forge script script/00_Brianker_Deployer.s.sol:BriankerHookDeployer --rpc-url <RPC_URL> --private-key <PRIVATE_KEY> --broadcast 
```

Note this will require 0.001 ( 1e15 ) native currency in your wallet, otherwise you can lower the values in the script wich:
- deploys the hook
- execute a swap, for tests purpose


---

### Check Forge Installation
*Ensure that you have correctly installed Foundry (Forge) and that it's up to date. You can update Foundry by running:*

```
foundryup
```




