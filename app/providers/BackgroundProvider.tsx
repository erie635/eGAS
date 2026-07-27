// app/providers/BackgroundProvider.tsx
'use client';

import { useEffect } from 'react';
import { db, auth } from '../../lib/firebase';
import { doc, getDoc } from 'firebase/firestore';

export function BackgroundProvider({ children }: { children: React.ReactNode }) {
  useEffect(() => {
    const fetchBackground = async () => {
      const currentUser = auth.currentUser;
      if (!currentUser) {
        document.documentElement.style.backgroundColor = '#f3f4f6';
        document.documentElement.style.minHeight = '100vh';
        return;
      }

      try {
        const userRef = doc(db, 'users', currentUser.uid);
        const docSnap = await getDoc(userRef);
        
        if (docSnap.exists()) {
          const data = docSnap.data();
          const bg = data.background || 'white';
          
          const bgColors: { [key: string]: string } = {
            'dark': '#111827',
            'skyblue': '#93c5fd',
            'gray': '#e5e7eb',
            'white': '#f3f4f6'
          };
          document.documentElement.style.backgroundColor = bgColors[bg] || '#f3f4f6';
          document.documentElement.style.minHeight = '100vh';
        }
      } catch (error) {
        console.error('Error fetching background:', error);
      }
    };

    fetchBackground();
  }, []);

  return <>{children}</>;
}