'use client';

import { useState, useEffect } from 'react';
import { db, auth } from '../../../lib/firebase';
import { doc, onSnapshot } from 'firebase/firestore';
import { getDoc } from 'firebase/firestore';
import Link from 'next/link';

export default function CompanyFuelStock() {
  const [loading, setLoading] = useState(true);
  const [fuelStock, setFuelStock] = useState({
    Petrol: 0,
    Diesel: 0,
    Kerosene: 0,
    'V-Power': 0
  });
  const [lastUpdated, setLastUpdated] = useState(null);
  const [totalCapacity, setTotalCapacity] = useState(400000); // 100,000 per tank
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

  // Listen to main tank stock from company/fuelStock
  useEffect(() => {
    const unsubscribe = onSnapshot(doc(db, 'company', 'fuelStock'), (docSnap) => {
      if (docSnap.exists()) {
        const data = docSnap.data();
        const stock = data.stock || { Petrol: 0, Diesel: 0, Kerosene: 0, 'V-Power': 0 };
        setFuelStock(stock);
        setLastUpdated(data.lastUpdated || new Date().toISOString());
        setLoading(false);
      } else {
        setLoading(false);
      }
    }, (error) => {
      console.error('Error listening to fuel stock:', error);
      setLoading(false);
    });

    return () => unsubscribe();
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

  // Get card class based on user preference
  const getCardClass = () => {
    switch (userBackground) {
      case 'dark':
        return 'bg-gray-800/95 border-gray-700 text-white';
      case 'skyblue':
        return 'bg-white/90 backdrop-blur-sm shadow-lg';
      case 'gray':
        return 'bg-white shadow-lg';
      default:
        return 'bg-white shadow-lg';
    }
  };

  // Calculate total combined fuel
  const calculateTotal = () => {
    return Object.values(fuelStock).reduce((sum, val) => sum + val, 0);
  };

  const calculatePercentage = (type) => {
    const amount = fuelStock[type] || 0;
    const capacity = 100000; // Each tank has 100,000L capacity
    return Math.min((amount / capacity) * 100, 100);
  };

  const getStatus = (type) => {
    const percentage = calculatePercentage(type);
    if (percentage >= 100) return { label: 'FULL', color: 'text-red-600', bg: 'bg-red-100' };
    if (percentage >= 80) return { label: 'Full', color: 'text-green-600', bg: 'bg-green-100' };
    if (percentage >= 50) return { label: 'Moderate', color: 'text-yellow-600', bg: 'bg-yellow-100' };
    if (percentage >= 20) return { label: 'Low', color: 'text-orange-600', bg: 'bg-orange-100' };
    return { label: 'Critical', color: 'text-red-600', bg: 'bg-red-100' };
  };

  const total = calculateTotal();
  const overallPercentage = Math.min((total / totalCapacity) * 100, 100);

  if (loading) {
    return (
      <div className={`flex items-center justify-center min-h-[60vh] ${getBackgroundClass()}`}>
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-green-500"></div>
      </div>
    );
  }

  return (
    <div className={`p-4 md:p-6 transition-colors duration-300 ${getBackgroundClass()}`}>
      <div className="max-w-7xl mx-auto space-y-6">
        <div className="flex items-center justify-between">
          <div>
            <h1 className={`text-2xl font-bold ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'}`}> Main Tank Stock</h1>
            <p className={`text-sm ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>
              Real-time fuel stock levels from main tanks
            </p>
          </div>
          <Link href="/fuel" className={`text-sm ${userBackground === 'dark' ? 'text-gray-400 hover:text-gray-200' : 'text-gray-500 hover:text-gray-700'} flex items-center space-x-1`}>
            <span>←</span>
            <span>Back to Fuel</span>
          </Link>
        </div>

       {/* Overall Stock Status */}
<div className={`rounded-xl shadow-lg p-6 border ${userBackground === 'dark' ? 'bg-blue-800' : 'bg-gradient-to-br from-blue-50 to-cyan-900 border-blue-200'} hover:shadow-xl transition-all duration-300`}>
  {/* CHANGE 1: Added gradient backgrounds (to-br from-blue to-cyan) for depth, hover shadow, and transition */}
  
  <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
    <div>
      <h2 className={`text-lg font-semibold ${userBackground === 'dark' ? 'text-white' : 'text-red-900'}`}> Total Fuel Stock</h2>
      <p className={`text-sm ${userBackground === 'dark' ? 'text-gray-900' : 'text-gray-900'}`}>Total Capacity: {totalCapacity.toLocaleString()} Liters</p>
      {/* CHANGE 2: Dark mode text color from 'text-gray-400' to 'text-gray-300' for better contrast */}
    </div>
    <div className="flex items-center space-x-4">
      <span className={`text-3xl font-bold ${userBackground === 'dark' ? 'text-blue-300' : 'text-blue-700'}`}>
        {/* CHANGE 3: Text size from 'text-2xl' to 'text-3xl' for better visibility */}
        {/* CHANGE 4: Dark mode text color from 'text-blue-400' to 'text-blue-300' for better contrast */}
        {total.toFixed(1)}L
      </span>
      <span className={`text-sm ${userBackground === 'dark' ? 'text-gray-400' : 'text-red-800'}`}>
        / {totalCapacity.toLocaleString()}L
      </span>
      <span className={`px-4 py-1.5 rounded-full text-sm font-semibold ${
        /* CHANGE 5: Padding increased from 'px-3 py-1' to 'px-4 py-1.5' for better touch target */
        /* CHANGE 6: Font weight from 'font-medium' to 'font-semibold' for better readability */
        overallPercentage >= 100 ? 'bg-red-500 text-white' :
        overallPercentage >= 80 ? 'bg-green-500 text-white' :
        overallPercentage >= 50 ? 'bg-yellow-500 text-white' :
        overallPercentage >= 20 ? 'bg-orange-500 text-white' :
        'bg-red-500 text-white'
        /* CHANGE 7: All badges now have white text on solid colors for better contrast */
        /* Previously: bg-red-100 text-red-700 (low contrast) */
      }`}>
        {overallPercentage >= 100 ? '🔴 FULL' : `${overallPercentage.toFixed(1)}%`}
      </span>
    </div>
  </div>
  
  <div className="mt-4">
    <div className={`w-full rounded-full h-4 overflow-hidden ${userBackground === 'dark' ? 'bg-gray-700/50' : 'bg-gray-100'}`}>
      {/* CHANGE 8: Progress bar background from 'bg-gray-700' to 'bg-gray-700/50' for transparency in dark mode */}
      {/* CHANGE 9: Light mode background from 'bg-white' to 'bg-gray-100' for better visibility */}
      
      <div 
        className={`h-full transition-all duration-1000 ${
          overallPercentage >= 100 ? 'bg-gradient-to-r from-red-500 to-red-600' :
          overallPercentage >= 80 ? 'bg-gradient-to-r from-emerald-500 to-green-500' :
          overallPercentage >= 50 ? 'bg-gradient-to-r from-yellow-400 to-yellow-500' :
          overallPercentage >= 20 ? 'bg-gradient-to-r from-orange-400 to-orange-500' :
          'bg-gradient-to-r from-red-500 to-red-600'
          /* CHANGE 10: Added gradients to progress bar for visual appeal */
          /* CHANGE 11: Changed 'bg-green-500' to 'bg-gradient-to-r from-emerald-500 to-green-500' */
          /* CHANGE 12: Changed 'bg-yellow-500' to 'bg-gradient-to-r from-yellow-400 to-yellow-500' */
          /* CHANGE 13: Changed 'bg-orange-500' to 'bg-gradient-to-r from-orange-400 to-orange-500' */
        }`}
        style={{ width: `${Math.min(overallPercentage, 100)}%` }}
      />
    </div>
  </div>
  
  {lastUpdated && (
    <p className={`text-xs ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-800'} mt-3`}>
      {/* CHANGE 14: Margin top from 'mt-2' to 'mt-3' for better spacing */}
      {/* CHANGE 15: Added clock emoji for visual cue */}
      🕐 Last updated: {new Date(lastUpdated).toLocaleString()}
    </p>
  )}
</div>

        {/* Fuel Stock Table - View Only */}
        <div className={`rounded-xl shadow-sm border ${userBackground === 'dark' ? 'border-gray-700' : 'border-gray-100'} ${getCardClass()}`}>
          <div className={`p-4 border-b ${userBackground === 'dark' ? 'border-gray-700 bg-gray-800/50' : 'border-gray-200 bg-gray-50'}`}>
            <div className="flex items-center justify-between">
              <h2 className={`text-lg font-semibold ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'}`}> Current Main Tank Levels</h2>
              <span className={`text-xs ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-400'}`}>🔒 View Only - Managed via Imports</span>
            </div>
          </div>

          <div className="overflow-x-auto">
            <table className="w-full">
              <thead className={userBackground === 'dark' ? 'bg-gray-800' : 'bg-gray-600'}>
                <tr>
                  <th className={`px-6 py-3 text-left text-xs font-medium uppercase tracking-wider ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-200'}`}>Fuel Type</th>
                  <th className={`px-6 py-3 text-left text-xs font-medium uppercase tracking-wider ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-200'}`}>Current Stock (L)</th>
                  <th className={`px-6 py-3 text-left text-xs font-medium uppercase tracking-wider ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-200'}`}>Capacity (L)</th>
                  <th className={`px-6 py-3 text-left text-xs font-medium uppercase tracking-wider ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-200'}`}>Status</th>
                  <th className={`px-6 py-3 text-left text-xs font-medium uppercase tracking-wider ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-200'}`}>Percentage</th>
                </tr>
              </thead>
              <tbody className={`divide-y ${userBackground === 'dark' ? 'divide-gray-700' : 'divide-gray-200'}`}>
                {Object.keys(fuelStock).map((fuelType) => {
                  const status = getStatus(fuelType);
                  const percentage = calculatePercentage(fuelType);
                  const amount = fuelStock[fuelType] || 0;
                  const isFull = percentage >= 100;
                  
                  return (
                    <tr key={fuelType} className={userBackground === 'dark' ? 'hover:bg-gray-800/50' : 'hover:bg-gray-50'}>
                      <td className="px-6 py-4 whitespace-nowrap">
                        <div className="flex items-center space-x-2">
                          <span className={`font-semibold ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'}`}>{fuelType}</span>
                          <span className={`px-2 py-1 text-xs rounded-full ${status.bg} ${status.color}`}>
                            {status.label}
                          </span>
                          {isFull && (
                            <span className="px-2 py-1 text-xs rounded-full bg-red-100 text-red-600 font-bold animate-pulse">
                              🚫 FULL
                            </span>
                          )}
                        </div>
                      </td>
                      <td className="px-6 py-4">
                        <span className={`text-sm font-medium ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'}`}>{amount.toFixed(1)}L</span>
                      </td>
                      <td className="px-6 py-4">
                        <span className={`text-sm ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>100,000L</span>
                      </td>
                      <td className="px-6 py-4">
                        <div className="flex items-center space-x-2">
                          <div className={`w-24 rounded-full h-2 ${userBackground === 'dark' ? 'bg-gray-700' : 'bg-gray-200'}`}>
                            <div 
                              className={`h-2 rounded-full ${
                                isFull ? 'bg-red-500' :
                                percentage >= 80 ? 'bg-green-500' :
                                percentage >= 50 ? 'bg-yellow-500' :
                                percentage >= 20 ? 'bg-orange-500' :
                                'bg-red-500'
                              }`}
                              style={{ width: `${Math.min(percentage, 100)}%` }}
                            />
                          </div>
                          <span className={`text-xs ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>{percentage.toFixed(0)}%</span>
                        </div>
                      </td>
                      <td className="px-6 py-4">
                        <span className={`text-sm font-medium ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'}`}>
                          {percentage.toFixed(1)}%
                        </span>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>

        {/* Info Section */}
        <div className={`p-4 rounded-lg border ${userBackground === 'dark' ? 'bg-cyan-500/30 border-cyan-700 text-cyan-200' : 'bg-cyan-500 border-cyan-200 text-cyan-700'}`}>
          <div className="flex flex-wrap items-center justify-between gap-2">
            <div className="flex items-center space-x-4">
              <span className={`text-sm font-medium ${userBackground === 'dark' ? 'text-gray-100' : 'text-gray-200'}`}>ℹ️ Information:</span>
              <span className={`text-sm ${userBackground === 'dark' ? 'text-cyan-300' : 'text-red-900'}`}>Fuel levels are automatically managed through imports</span>
            </div>
            <div className={`text-sm ${userBackground === 'dark' ? 'text-cyan-300' : 'text-red-900'}`}>
              💡 Fuel is added only via the Import Fuel page
            </div>
          </div>
        </div>

        {/* Legend */}
        <div className={`rounded-lg p-4 border ${userBackground === 'dark' ? 'border-gray-700 bg-gray-800/50' : 'border-gray-200 bg-gray-50'}`}>
          <div className="flex flex-wrap items-center gap-4 text-sm">
            <span className={`font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'}`}>Status Legend:</span>
            <span className="flex items-center space-x-1">
              <span className="w-3 h-3 bg-red-500 rounded-full"></span>
              <span className={userBackground === 'dark' ? 'text-gray-300' : 'text-gray-600'}>Full (100%)</span>
            </span>
            <span className="flex items-center space-x-1">
              <span className="w-3 h-3 bg-green-500 rounded-full"></span>
              <span className={userBackground === 'dark' ? 'text-gray-300' : 'text-gray-600'}>Full (80%+)</span>
            </span>
            <span className="flex items-center space-x-1">
              <span className="w-3 h-3 bg-yellow-500 rounded-full"></span>
              <span className={userBackground === 'dark' ? 'text-gray-300' : 'text-gray-600'}>Moderate (50-80%)</span>
            </span>
            <span className="flex items-center space-x-1">
              <span className="w-3 h-3 bg-orange-500 rounded-full"></span>
              <span className={userBackground === 'dark' ? 'text-gray-300' : 'text-gray-600'}>Low (20-50%)</span>
            </span>
            <span className="flex items-center space-x-1">
              <span className="w-3 h-3 bg-red-500 rounded-full"></span>
              <span className={userBackground === 'dark' ? 'text-gray-300' : 'text-gray-600'}>Critical (0-20%)</span>
            </span>
          </div>
        </div>
      </div>
    </div>
  );
}