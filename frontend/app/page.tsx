"use client";

import { ConnectButton } from "@rainbow-me/rainbowkit";
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { parseEther, formatEther } from "viem";
import { useState, useEffect } from "react";
import { MINI_DEX_ADDRESS, MINI_DEX_ABI, ERC20_ABI, ALPHA_ADDRESS, BETA_ADDRESS } from "./abi";

export default function Home() {
  const { address, isConnected } = useAccount();
  const [amountA, setAmountA] = useState("10");
  const [amountB, setAmountB] = useState("10");
  const [slippage, setSlippage] = useState("50");
  const [withdrawLp, setWithdrawLp] = useState("");
  const [approveStep, setApproveStep] = useState<"a" | "b" | "done">("a");
  const [txMsg, setTxMsg] = useState("");

  // Balances
  const { data: balA, refetch: refetchBalA } = useReadContract({
    address: ALPHA_ADDRESS, abi: ERC20_ABI, functionName: "balanceOf",
    args: address ? [address] : undefined, query: { enabled: !!address },
  });
  const { data: balB, refetch: refetchBalB } = useReadContract({
    address: BETA_ADDRESS, abi: ERC20_ABI, functionName: "balanceOf",
    args: address ? [address] : undefined, query: { enabled: !!address },
  });

  // Allowances
  const { data: allowA, refetch: refetchAllowA } = useReadContract({
    address: ALPHA_ADDRESS, abi: ERC20_ABI, functionName: "allowance",
    args: address ? [address, MINI_DEX_ADDRESS] : undefined, query: { enabled: !!address },
  });
  const { data: allowB, refetch: refetchAllowB } = useReadContract({
    address: BETA_ADDRESS, abi: ERC20_ABI, functionName: "allowance",
    args: address ? [address, MINI_DEX_ADDRESS] : undefined, query: { enabled: !!address },
  });

  // Position & pool share
  const { data: position, refetch: refetchPosition } = useReadContract({
    address: MINI_DEX_ADDRESS, abi: MINI_DEX_ABI, functionName: "getPosition",
    args: address ? [address, ALPHA_ADDRESS, BETA_ADDRESS] : undefined, query: { enabled: !!address },
  });
  const { data: poolShareBps, refetch: refetchShare } = useReadContract({
    address: MINI_DEX_ADDRESS, abi: MINI_DEX_ABI, functionName: "getPoolShareBps",
    args: address ? [address, ALPHA_ADDRESS, BETA_ADDRESS] : undefined, query: { enabled: !!address },
  });

  const { writeContract, data: txHash, isPending } = useWriteContract();
  const { isSuccess } = useWaitForTransactionReceipt({ hash: txHash });

  const parsedA = amountA ? parseEther(amountA) : 0n;
  const parsedB = amountB ? parseEther(amountB) : 0n;
  const needsApproveA = (allowA as bigint ?? 0n) < parsedA;
  const needsApproveB = (allowB as bigint ?? 0n) < parsedB;

  useEffect(() => {
    if (needsApproveA) setApproveStep("a");
    else if (needsApproveB) setApproveStep("b");
    else setApproveStep("done");
  }, [needsApproveA, needsApproveB]);

  useEffect(() => {
    if (isSuccess) {
      refetchBalA(); refetchBalB();
      refetchAllowA(); refetchAllowB();
      refetchPosition(); refetchShare();
      setTxMsg("Transaction confirmed!");
      setTimeout(() => setTxMsg(""), 4000);
    }
  }, [isSuccess, refetchBalA, refetchBalB, refetchAllowA, refetchAllowB, refetchPosition, refetchShare]);

  const handleMint = () => {
    if (!address) return;
    writeContract({ address: ALPHA_ADDRESS, abi: ERC20_ABI, functionName: "mint", args: [address, parseEther("100")] });
  };
  const handleMintB = () => {
    if (!address) return;
    writeContract({ address: BETA_ADDRESS, abi: ERC20_ABI, functionName: "mint", args: [address, parseEther("100")] });
  };

  const handleApproveA = () => writeContract({
    address: ALPHA_ADDRESS, abi: ERC20_ABI, functionName: "approve", args: [MINI_DEX_ADDRESS, parsedA],
  });
  const handleApproveB = () => writeContract({
    address: BETA_ADDRESS, abi: ERC20_ABI, functionName: "approve", args: [MINI_DEX_ADDRESS, parsedB],
  });

  const handleDeposit = () => {
    const deadline = BigInt(Math.floor(Date.now() / 1000) + 600);
    writeContract({
      address: MINI_DEX_ADDRESS, abi: MINI_DEX_ABI, functionName: "deposit",
      args: [ALPHA_ADDRESS, BETA_ADDRESS, parsedA, parsedB, BigInt(slippage), deadline],
    });
  };

  const handleWithdraw = () => {
    if (!withdrawLp) return;
    const deadline = BigInt(Math.floor(Date.now() / 1000) + 600);
    writeContract({
      address: MINI_DEX_ADDRESS, abi: MINI_DEX_ABI, functionName: "withdraw",
      args: [ALPHA_ADDRESS, BETA_ADDRESS, parseEther(withdrawLp), BigInt(slippage), deadline],
    });
  };

  const lpPosition = position as bigint ?? 0n;
  const poolShare = poolShareBps as bigint ?? 0n;

  return (
    <main className="min-h-screen p-4 md:p-8 max-w-2xl mx-auto">
      <div className="flex items-center justify-between mb-8">
        <div>
          <h1 className="text-2xl font-bold text-teal-400">💧 MiniDEX</h1>
          <p className="text-sm text-white/50">Liquidity vault on Uniswap V2 · Sepolia</p>
        </div>
        <ConnectButton />
      </div>

      {!isConnected ? (
        <div className="rounded-2xl border border-white/10 bg-white/5 p-12 text-center">
          <p className="text-4xl mb-4">💧</p>
          <p className="text-white/60">Connect your wallet to provide liquidity.</p>
        </div>
      ) : (
        <div className="space-y-4">
          {/* Position */}
          <div className="rounded-2xl border border-white/10 bg-white/5 p-6">
            <h2 className="font-semibold mb-4 text-teal-400">📊 Your Position (ALPHA / BETA)</h2>
            <div className="grid grid-cols-3 gap-4 text-center">
              <div>
                <p className="text-xs text-white/50">ALPHA Balance</p>
                <p className="text-xl font-bold text-white">{balA !== undefined ? Number(formatEther(balA as bigint)).toFixed(2) : "0"}</p>
              </div>
              <div>
                <p className="text-xs text-white/50">BETA Balance</p>
                <p className="text-xl font-bold text-white">{balB !== undefined ? Number(formatEther(balB as bigint)).toFixed(2) : "0"}</p>
              </div>
              <div>
                <p className="text-xs text-white/50">LP in Vault</p>
                <p className="text-xl font-bold text-teal-400">{Number(formatEther(lpPosition)).toFixed(6)}</p>
              </div>
            </div>
            {poolShare > 0n && (
              <p className="text-xs text-center text-white/40 mt-3">
                Pool share: <span className="text-teal-400">{(Number(poolShare) / 100).toFixed(4)}%</span>
              </p>
            )}
          </div>

          {/* Faucet */}
          <div className="rounded-2xl border border-white/10 bg-white/5 p-6">
            <h2 className="font-semibold mb-3 text-teal-400">🪙 Get Test Tokens</h2>
            <div className="flex gap-2">
              <button onClick={handleMint} disabled={isPending}
                className="flex-1 bg-white/10 hover:bg-white/20 disabled:opacity-40 text-white font-semibold py-2 rounded-xl text-sm transition-colors">
                {isPending ? "..." : "Mint 100 ALPHA"}
              </button>
              <button onClick={handleMintB} disabled={isPending}
                className="flex-1 bg-white/10 hover:bg-white/20 disabled:opacity-40 text-white font-semibold py-2 rounded-xl text-sm transition-colors">
                {isPending ? "..." : "Mint 100 BETA"}
              </button>
            </div>
          </div>

          {/* Deposit */}
          <div className="rounded-2xl border border-white/10 bg-white/5 p-6">
            <h2 className="font-semibold mb-4 text-teal-400">➕ Add Liquidity</h2>
            <div className="space-y-3">
              <div className="grid grid-cols-2 gap-2">
                <div>
                  <label className="text-xs text-white/50">ALPHA amount</label>
                  <input type="number" min="0" value={amountA} onChange={(e) => setAmountA(e.target.value)}
                    className="w-full bg-white/10 border border-white/20 rounded-xl px-4 py-2 text-white focus:outline-none focus:border-teal-400" />
                </div>
                <div>
                  <label className="text-xs text-white/50">BETA amount</label>
                  <input type="number" min="0" value={amountB} onChange={(e) => setAmountB(e.target.value)}
                    className="w-full bg-white/10 border border-white/20 rounded-xl px-4 py-2 text-white focus:outline-none focus:border-teal-400" />
                </div>
              </div>
              <div>
                <label className="text-xs text-white/50">Slippage (bps) — {(Number(slippage) / 100).toFixed(2)}%</label>
                <input type="number" min="0" max="1000" value={slippage} onChange={(e) => setSlippage(e.target.value)}
                  className="w-full bg-white/10 border border-white/20 rounded-xl px-4 py-2 text-white focus:outline-none focus:border-teal-400" />
              </div>
              {approveStep === "a" && (
                <button onClick={handleApproveA} disabled={isPending || parsedA === 0n}
                  className="w-full bg-teal-500 hover:bg-teal-400 disabled:opacity-40 text-black font-semibold py-2 rounded-xl transition-colors">
                  {isPending ? "..." : "① Approve ALPHA"}
                </button>
              )}
              {approveStep === "b" && (
                <button onClick={handleApproveB} disabled={isPending || parsedB === 0n}
                  className="w-full bg-teal-500 hover:bg-teal-400 disabled:opacity-40 text-black font-semibold py-2 rounded-xl transition-colors">
                  {isPending ? "..." : "② Approve BETA"}
                </button>
              )}
              {approveStep === "done" && (
                <button onClick={handleDeposit} disabled={isPending || parsedA === 0n || parsedB === 0n}
                  className="w-full bg-teal-500 hover:bg-teal-400 disabled:opacity-40 text-black font-semibold py-2 rounded-xl transition-colors">
                  {isPending ? "..." : "③ Add Liquidity"}
                </button>
              )}
            </div>
          </div>

          {/* Withdraw */}
          {lpPosition > 0n && (
            <div className="rounded-2xl border border-teal-400/30 bg-teal-400/5 p-6">
              <h2 className="font-semibold mb-4 text-teal-400">➖ Remove Liquidity</h2>
              <div className="space-y-2">
                <div>
                  <label className="text-xs text-white/50">LP tokens to withdraw (max: {Number(formatEther(lpPosition)).toFixed(6)})</label>
                  <input type="number" min="0" value={withdrawLp} onChange={(e) => setWithdrawLp(e.target.value)}
                    placeholder={Number(formatEther(lpPosition)).toFixed(6)}
                    className="w-full bg-white/10 border border-white/20 rounded-xl px-4 py-2 text-white focus:outline-none focus:border-teal-400" />
                </div>
                <button onClick={handleWithdraw} disabled={isPending || !withdrawLp}
                  className="w-full bg-teal-500 hover:bg-teal-400 disabled:opacity-40 text-black font-semibold py-2 rounded-xl transition-colors">
                  {isPending ? "..." : "Remove Liquidity"}
                </button>
              </div>
            </div>
          )}

          {/* Tx feedback */}
          {txMsg && (
            <div className="rounded-xl border border-green-400/30 bg-green-400/10 p-4 text-green-400 text-sm text-center">
              ✅ {txMsg}
            </div>
          )}
          {txHash && !isSuccess && (
            <div className="rounded-xl border border-white/10 bg-white/5 p-4 text-xs text-white/50 text-center">
              Waiting for confirmation...{" "}
              <a href={`https://sepolia.etherscan.io/tx/${txHash}`} target="_blank" className="text-teal-400 underline">
                View on Etherscan
              </a>
            </div>
          )}
        </div>
      )}

      <p className="text-center text-xs text-white/20 mt-8">
        MiniDEX:{" "}
        <a href={`https://sepolia.etherscan.io/address/${MINI_DEX_ADDRESS}`} target="_blank" className="underline hover:text-white/40">
          {MINI_DEX_ADDRESS.slice(0, 6)}...{MINI_DEX_ADDRESS.slice(-4)}
        </a>
      </p>
    </main>
  );
}
