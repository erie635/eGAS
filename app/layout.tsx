// app/layout.tsx
import './globals.css';
import { Inter } from 'next/font/google';
import { Toaster } from 'react-hot-toast';
import type { Metadata } from 'next';
import { BackgroundProvider } from './providers/BackgroundProvider';

const inter = Inter({ subsets: ['latin'] });

export const metadata: Metadata = {
  title: 'E-Fuel Admin',
  description: 'Fuel Management System',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body className={inter.className}>
        <BackgroundProvider>
          {children}
        </BackgroundProvider>
        <Toaster position="top-right" />
      </body>
    </html>
  );
}