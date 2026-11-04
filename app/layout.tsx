import type { Metadata } from "next";
import "./globals.css";
import { CartProvider } from "../components/cart-provider";

export const metadata: Metadata = {
  title: "Much More Electronics | More tech. More value.",
  description: "Shop new, used, and refurbished electronics at Much More Electronics.",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body><CartProvider>{children}</CartProvider></body></html>;
}
