import type { Metadata } from "next";
import "./globals.css";

const siteUrl = "https://www.muchmoreelectronics.com";

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  title: {
    default: "Much More Electronics | More Tech. More Value.",
    template: "%s | Much More Electronics",
  },
  description:
    "Discover new, pre-loved and refurbished electronics at Much More Electronics. Explore technology for work, home and everyday life.",
  alternates: {
    canonical: "/",
  },
  openGraph: {
    type: "website",
    url: siteUrl,
    siteName: "Much More Electronics",
    title: "Much More Electronics | More Tech. More Value.",
    description:
      "Discover new, pre-loved and refurbished electronics at Much More Electronics.",
  },
  twitter: {
    card: "summary",
    title: "Much More Electronics | More Tech. More Value.",
    description:
      "Discover new, pre-loved and refurbished electronics at Much More Electronics.",
  },
  robots: {
    index: true,
    follow: true,
  },
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
