import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Much More Electronics | More tech. More value.",
  description: "Shop new, used, and refurbished electronics at Much More Electronics.",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>;
}
