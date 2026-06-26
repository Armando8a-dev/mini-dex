export const MINI_DEX_ADDRESS = "0x93852eB43E1739F3691a984cF4F51047d8cCa1C8" as const;

// Same ALPHA/BETA tokens with V2 liquidity used in BestSwap
export const ALPHA_ADDRESS = "0xa1CFD0Acf5E12928CC82Af96aAC145A7e61beF33" as const;
export const BETA_ADDRESS  = "0xa6b347ca0412b4632621E8943402F99f7f5C5328" as const;

export const MINI_DEX_ABI = [
  {
    type: "function", name: "router",
    inputs: [], outputs: [{ type: "address" }], stateMutability: "view",
  },
  {
    type: "function", name: "factory",
    inputs: [], outputs: [{ type: "address" }], stateMutability: "view",
  },
  {
    type: "function", name: "getPosition",
    inputs: [{ type: "address" }, { type: "address" }, { type: "address" }],
    outputs: [{ type: "uint256" }], stateMutability: "view",
  },
  {
    type: "function", name: "getPoolShareBps",
    inputs: [{ type: "address" }, { type: "address" }, { type: "address" }],
    outputs: [{ type: "uint256" }], stateMutability: "view",
  },
  {
    type: "function", name: "deposit",
    inputs: [
      { name: "tokenA", type: "address" },
      { name: "tokenB", type: "address" },
      { name: "amountADesired", type: "uint256" },
      { name: "amountBDesired", type: "uint256" },
      { name: "maxSlippageBps", type: "uint256" },
      { name: "deadline", type: "uint256" },
    ],
    outputs: [{ name: "lpTokens", type: "uint256" }],
    stateMutability: "nonpayable",
  },
  {
    type: "function", name: "withdraw",
    inputs: [
      { name: "tokenA", type: "address" },
      { name: "tokenB", type: "address" },
      { name: "lpAmount", type: "uint256" },
      { name: "maxSlippageBps", type: "uint256" },
      { name: "deadline", type: "uint256" },
    ],
    outputs: [{ name: "amountA", type: "uint256" }, { name: "amountB", type: "uint256" }],
    stateMutability: "nonpayable",
  },
] as const;

export const ERC20_ABI = [
  { type: "function", name: "symbol", inputs: [], outputs: [{ type: "string" }], stateMutability: "view" },
  { type: "function", name: "balanceOf", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "allowance", inputs: [{ type: "address" }, { type: "address" }], outputs: [{ type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "approve", inputs: [{ type: "address" }, { type: "uint256" }], outputs: [{ type: "bool" }], stateMutability: "nonpayable" },
  { type: "function", name: "mint", inputs: [{ type: "address" }, { type: "uint256" }], outputs: [], stateMutability: "nonpayable" },
] as const;
