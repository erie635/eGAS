// app/fuel/page.js
'use client';

import { useState, useEffect } from 'react';
import Link from 'next/link';
import { auth, db } from '../../lib/firebase';
import { doc, getDoc } from 'firebase/firestore';

export default function FuelPage() {
  const [userBackground, setUserBackground] = useState('white');

  // Fetch user background
  useEffect(() => {
    const fetchUserBackground = async () => {
      const currentUser = auth.currentUser;
      if (!currentUser) return;

      try {
        const userDoc = await getDoc(doc(db, 'users', currentUser.uid));
        if (userDoc.exists()) {
          const data = userDoc.data();
          if (data.background) {
            setUserBackground(data.background);
          }
        }
      } catch (error) {
        console.error('Error fetching user background:', error);
      }
    };

    fetchUserBackground();
  }, []);

  // Get background class based on user preference
  const getBackgroundClass = () => {
    switch (userBackground) {
      case 'dark':
        return 'bg-gray-900 text-white min-h-screen';
      case 'skyblue':
        return 'bg-gradient-to-br from-blue-100 to-blue-300 min-h-screen';
      case 'gray':
        return 'bg-gray-200 min-h-screen';
      default:
        return 'bg-gray-100 min-h-screen';
    }
  };

  return (
    <div className={`p-4 md:p-6 transition-colors duration-300 ${getBackgroundClass()}`}>
      <div className="max-w-7xl mx-auto space-y-6">
        <div>
          <h1 className={`text-2xl font-bold ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'}`}>Fuel Management</h1>
          <p className={`text-sm ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>
            Manage fuel inventory and distribution
          </p>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          <Link href="/fuel/tanks" className="rounded-xl shadow-sm p-6 border hover:shadow-md transition bg-blue-500 border-blue-200">
            <div className="flex items-center space-x-4">
              <div className="p-3 bg-blue-200 rounded-lg">
                <span className="text-2xl">🛢️</span>
              </div>
              <div>
                <h3 className="font-semibold text-gray-900">Tank Status</h3>
                <p className="text-sm text-gray-800">View fuel levels</p>
              </div>
            </div>
          </Link>

          <Link href="/fuel/import" className="rounded-xl shadow-sm p-6 border hover:shadow-md transition bg-green-500 border-green-200">
            <div className="flex items-center space-x-4">
              <div className="p-3 bg-green-200 rounded-lg">
                <span className="text-2xl">📥</span>
              </div>
              <div>
                <h3 className="font-semibold text-gray-900">Import Fuel</h3>
                <p className="text-sm text-gray-800">Add fuel to system</p>
              </div>
            </div>
          </Link>

          <Link href="/fuel/update" className="rounded-xl shadow-sm p-6 border hover:shadow-md transition bg-purple-400 border-purple-200">
            <div className="flex items-center space-x-4">
              <div className="p-3 bg-purple-200 rounded-lg">
                <span className="text-2xl">📊</span>
              </div>
              <div>
                <h3 className="font-semibold text-gray-900">Update Fuel</h3>
                <p className="text-sm text-gray-800">Update driver fuel</p>
              </div>
            </div>
          </Link>
        </div>
      </div>
    </div>
  );
}