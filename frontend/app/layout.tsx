import type { Metadata } from "next";
import { Providers } from "./providers";
import "./globals.css";

export const metadata: Metadata = {
  title: "MiniDEX — Liquidity Vault on Uniswap V2",
  description: "Deposit token pairs to add liquidity. LP tokens held in vault. Withdraw anytime with slippage protection.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
