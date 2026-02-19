import type { Metadata } from "next"
import { Inter } from "next/font/google"
import { Nav } from "@/components/nav"
import "./globals.css"

const inter = Inter({ subsets: ["latin"] })

export const metadata: Metadata = {
  title: "Factory Agents",
  description: "Dashboard for Codex automated issue implementation",
}

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode
}>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body className={`${inter.className} min-h-screen bg-background text-foreground antialiased`}>
        <Nav />
        <main className="mx-auto max-w-7xl p-6">{children}</main>
      </body>
    </html>
  )
}
