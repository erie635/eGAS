'use client';

import { useState, useEffect } from 'react';
import { db, auth } from '../../lib/firebase';
import { collection, getDocs, deleteDoc, doc, onSnapshot, setDoc, updateDoc, serverTimestamp, getDoc } from 'firebase/firestore';
import Link from 'next/link';
import toast from 'react-hot-toast';

interface Driver {
  id: string;
  name: string;
  email: string;
  phone: string;
  isOnline: boolean;
  vehicleType?: string;
  numberPlate?: string;
  status?: string;
  lastSeen?: Date;
  onlineSince?: Date;
  offlineSince?: Date;
  lastStatusChange?: Date;
  todayStartTime?: Date;
  todayTotalHours?: number;
  todayTotalMinutes?: number;
  dailyActivityId?: string;
  remainingFuel?: {
    Petrol?: number;
    Diesel?: number;
    Kerosene?: number;
    'V-Power'?: number;
  };
}

interface DriverWithDuration extends Driver {
  duration: string;
  statusTime: string;
  todayHours: string;
}

export default function DriversPage() {
  const [drivers, setDrivers] = useState<DriverWithDuration[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');
  const [initialLoadComplete, setInitialLoadComplete] = useState(false);
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
        return 'bg-gray-900 text-white';
      case 'skyblue':
        return 'bg-gradient-to-br from-blue-100 to-blue-300';
      case 'gray':
        return 'bg-gray-200';
      default:
        return 'bg-gray-100';
    }
  };

  // Get card class based on user preference
  const getCardClass = () => {
    switch (userBackground) {
      case 'dark':
        return 'bg-gray-800/95 border-gray-700';
      case 'skyblue':
        return 'bg-white/90 backdrop-blur-sm shadow-lg';
      case 'gray':
        return 'bg-white shadow-lg';
      default:
        return 'bg-white shadow-lg';
    }
  };

  // Function to format fuel value
  const formatFuelValue = (value: number | undefined) => {
    if (value === undefined || value === null || value === 0) {
      return '0L';
    }
    return `${value.toFixed(2)}L`;
  };

  // Function to calculate and save daily activity
  const updateDailyActivity = async (driver: Driver) => {
    try {
      const today = new Date();
      const dateStr = today.toISOString().split('T')[0];
      const activityId = `${driver.id}_${dateStr}`;
      
      const activityRef = doc(db, 'driverDailyActivity', activityId);
      
      // Ensure isOnline is always a boolean
      const isOnline = driver.isOnline ?? false;
      
      let activityData: any = {
        driverId: driver.id,
        driverName: driver.name || 'Unknown',
        numberPlate: driver.numberPlate || '',
        date: dateStr,
        lastUpdated: serverTimestamp(),
        isOnline: isOnline,
        status: driver.status || 'unknown',
      };

      if (isOnline) {
        if (!driver.onlineSince) {
          activityData.onlineStart = serverTimestamp();
          activityData.totalMinutes = 0;
          activityData.totalHours = 0;
          activityData.lastOnlineTime = serverTimestamp();
        } else {
          activityData.lastOnlineTime = serverTimestamp();
        }
        activityData.offlineStart = null;
        activityData.lastOfflineTime = null;
      } else {
        if (!driver.offlineSince) {
          activityData.offlineStart = serverTimestamp();
        }
        activityData.lastOfflineTime = serverTimestamp();
        activityData.onlineStart = null;
        activityData.lastOnlineTime = null;
        
        if (driver.onlineSince) {
          const onlineStart = driver.onlineSince instanceof Date ? driver.onlineSince : new Date(driver.onlineSince);
          const now = new Date();
          const diffMs = now.getTime() - onlineStart.getTime();
          const diffMinutes = Math.floor(diffMs / (1000 * 60));
          const diffHours = Math.floor(diffMinutes / 60);
          const remainingMinutes = diffMinutes % 60;
          
          activityData.totalMinutes = diffMinutes;
          activityData.totalHours = diffHours;
          activityData.totalMinutesDisplay = remainingMinutes;
          activityData.lastOnlineTime = serverTimestamp();
        }
      }

      await setDoc(activityRef, activityData, { merge: true });
      
      const driverRef = doc(db, 'drivers', driver.id);
      await updateDoc(driverRef, {
        dailyActivityId: activityId,
        todayStartTime: isOnline ? serverTimestamp() : null,
        lastStatusChange: serverTimestamp(),
      });

    } catch (error) {
      console.error('Error updating daily activity:', error);
    }
  };

  // Calculate duration for display
  const calculateDuration = (driver: Driver): { duration: string; statusTime: string; todayHours: string } => {
    const now = new Date();
    let duration = '';
    let statusTime = '';
    let todayHours = '';

    if (driver.onlineSince) {
      const onlineStart = driver.onlineSince instanceof Date ? driver.onlineSince : new Date(driver.onlineSince);
      const diffMs = now.getTime() - onlineStart.getTime();
      const diffHrs = Math.floor(diffMs / (1000 * 60 * 60));
      const diffMins = Math.floor((diffMs % (1000 * 60 * 60)) / (1000 * 60));
      
      todayHours = `${diffHrs}h ${diffMins}m`;
    } else if (driver.todayTotalHours !== undefined) {
      todayHours = `${driver.todayTotalHours}h ${driver.todayTotalMinutes || 0}m`;
    } else {
      todayHours = '0h 0m';
    }

    if (driver.isOnline && driver.onlineSince) {
      const onlineTime = driver.onlineSince instanceof Date ? driver.onlineSince : new Date(driver.onlineSince);
      const diffMs = now.getTime() - onlineTime.getTime();
      const diffHrs = Math.floor(diffMs / (1000 * 60 * 60));
      const diffMins = Math.floor((diffMs % (1000 * 60 * 60)) / (1000 * 60));
      
      duration = `${diffHrs > 0 ? diffHrs + 'h ' : ''}${diffMins}m online`;
      statusTime = `Since ${onlineTime.toLocaleTimeString()}`;
    } 
    else if (!driver.isOnline && driver.offlineSince) {
      const offlineTime = driver.offlineSince instanceof Date ? driver.offlineSince : new Date(driver.offlineSince);
      const diffMs = now.getTime() - offlineTime.getTime();
      const diffHrs = Math.floor(diffMs / (1000 * 60 * 60));
      const diffMins = Math.floor((diffMs % (1000 * 60 * 60)) / (1000 * 60));
      
      duration = `${diffHrs > 0 ? diffHrs + 'h ' : ''}${diffMins}m offline`;
      statusTime = `Since ${offlineTime.toLocaleTimeString()}`;
    }
    else if (driver.lastSeen) {
      const lastSeenTime = driver.lastSeen instanceof Date ? driver.lastSeen : new Date(driver.lastSeen);
      const diffMs = now.getTime() - lastSeenTime.getTime();
      const diffMins = Math.floor(diffMs / (1000 * 60));
      duration = `Last seen ${diffMins}m ago`;
      statusTime = `At ${lastSeenTime.toLocaleTimeString()}`;
    } else {
      duration = 'Status unknown';
      statusTime = 'No timestamp';
    }

    return { duration, statusTime, todayHours };
  };

  useEffect(() => {
    const unsubscribe = onSnapshot(collection(db, 'drivers'), async (snapshot) => {
      try {
        const driversData = snapshot.docs.map(doc => {
          const data = doc.data();
          return {
            id: doc.id,
            ...data,
            lastSeen: data.lastSeen?.toDate?.() || data.lastSeen || null,
            onlineSince: data.onlineSince?.toDate?.() || data.onlineSince || null,
            offlineSince: data.offlineSince?.toDate?.() || data.offlineSince || null,
            lastStatusChange: data.lastStatusChange?.toDate?.() || data.lastStatusChange || null,
            todayStartTime: data.todayStartTime?.toDate?.() || data.todayStartTime || null,
            isOnline: data.isOnline ?? false,
            remainingFuel: data.remainingFuel || {},
          };
        }) as Driver[];

        const driversWithDuration = driversData.map(driver => {
          const { duration, statusTime, todayHours } = calculateDuration(driver);
          return {
            ...driver,
            duration,
            statusTime,
            todayHours
          };
        });

        setDrivers(driversWithDuration);
        setLoading(false);
        setInitialLoadComplete(true);

        if (driversData.length > 0) {
          Promise.all(driversData.map(driver => updateDailyActivity(driver)))
            .catch(err => console.error('Error updating daily activities:', err));
        }

      } catch (error) {
        console.error('Error processing drivers:', error);
        toast.error('Failed to load drivers');
        setLoading(false);
      }
    }, (error) => {
      console.error('Error fetching drivers:', error);
      toast.error('Failed to load drivers');
      setLoading(false);
    });

    return () => unsubscribe();
  }, []);

  const handleDelete = async (driverId: string, driverName: string) => {
    if (!confirm(`Are you sure you want to delete "${driverName}"?`)) return;
    
    try {
      await deleteDoc(doc(db, 'drivers', driverId));
      toast.success('Driver deleted successfully');
    } catch (error) {
      console.error('Error deleting driver:', error);
      toast.error('Failed to delete driver');
    }
  };

  const filteredDrivers = drivers.filter(driver =>
    driver.name?.toLowerCase().includes(searchTerm.toLowerCase()) ||
    driver.email?.toLowerCase().includes(searchTerm.toLowerCase()) ||
    driver.phone?.includes(searchTerm) ||
    driver.numberPlate?.toLowerCase().includes(searchTerm.toLowerCase())
  );

  if (loading) {
    return (
      <div className={`min-h-screen flex items-center justify-center ${getBackgroundClass()}`}>
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-green-500"></div>
      </div>
    );
  }

  return (
    <div className={`min-h-screen p-4 md:p-6 transition-colors duration-300 ${getBackgroundClass()}`}>
      <div className="max-w-7xl mx-auto space-y-6">
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <div>
            <h1 className="text-2xl font-bold">Drivers</h1>
            <p className={`text-sm mt-1 ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>
              Manage all drivers in the system
            </p>
          </div>
          <div className="flex flex-wrap gap-2">
            <Link 
              href="/drivers/add" 
              className="bg-green-500 hover:bg-green-600 text-white px-4 py-2 rounded-lg text-sm font-medium transition flex items-center space-x-2"
            >
              <span>+</span>
              <span>Add Driver</span>
            </Link>
          </div>
        </div>

        {/* Search Bar */}
        <div className="rounded-xl shadow-sm p-4 border bg-cyan-200 border-gray-200">
          <input
            type="text"
            placeholder="Search drivers by name, email, phone or plate number..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="w-full px-4 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500 bg-gray-200 border-gray-300"
          />
        </div>

        {/* Drivers Table */}
        <div className={`rounded-xl shadow-sm border ${userBackground === 'dark' ? 'border-gray-700' : 'border-gray-100'} ${getCardClass()}`}>
          <div className={`p-6 border-b ${userBackground === 'dark' ? 'border-gray-700' : 'border-gray-200'} flex justify-between items-center`}>
            <h2 className={`text-lg font-semibold ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'}`}>All Drivers</h2>
            <span className={`text-sm ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>{filteredDrivers.length} drivers</span>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead className={userBackground === 'dark' ? 'bg-gray-800' : 'bg-gray-600'}>
                <tr>
                  <th className={`px-6 py-3 text-left text-xs font-medium uppercase tracking-wider ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-200'}`}>Name</th>
                  <th className={`px-6 py-3 text-left text-xs font-medium uppercase tracking-wider ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-200'}`}>Email</th>
                  <th className={`px-6 py-3 text-left text-xs font-medium uppercase tracking-wider ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-200'}`}>Phone</th>
                  <th className={`px-6 py-3 text-left text-xs font-medium uppercase tracking-wider ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-200'}`}>Vehicle</th>
                  <th className={`px-6 py-3 text-left text-xs font-medium uppercase tracking-wider ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-200'}`}>Status</th>
                  <th className={`px-6 py-3 text-left text-xs font-medium uppercase tracking-wider ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-200'}`}>Actions</th>
                </tr>
              </thead>
              <tbody className={`divide-y ${userBackground === 'dark' ? 'divide-gray-700' : 'divide-gray-200'}`}>
                {filteredDrivers.length === 0 ? (
                  <tr>
                    <td colSpan="6" className={`px-6 py-8 text-center ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>
                      {searchTerm ? 'No drivers match your search' : 'No drivers found. Click "Add Driver" to create one.'}
                    </td>
                  </tr>
                ) : (
                  filteredDrivers.map((driver) => (
                    <tr key={driver.id} className={userBackground === 'dark' ? 'hover:bg-gray-800/50' : 'hover:bg-gray-50'}>
                      <td className="px-6 py-4 whitespace-nowrap">
                        <div className="flex items-center">
                          <div className="w-8 h-8 rounded-full bg-green-100 flex items-center justify-center text-green-600 font-semibold text-sm">
                            {driver.name?.charAt(0) || '?'}
                          </div>
                          <div className="ml-3">
                            <div className={`text-sm font-medium ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'}`}>{driver.name || 'N/A'}</div>
                            <div className={`text-xs ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>{driver.numberPlate || 'No plate'}</div>
                          </div>
                        </div>
                      </td>
                      <td className={`px-6 py-4 whitespace-nowrap text-sm ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-500'}`}>
                        {driver.email || 'N/A'}
                      </td>
                      <td className={`px-6 py-4 whitespace-nowrap text-sm ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-500'}`}>
                        {driver.phone || 'N/A'}
                      </td>
                      <td className={`px-6 py-4 whitespace-nowrap text-sm ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-500'}`}>
                        {driver.vehicleType || 'N/A'}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap">
                        <span className={`px-2 py-1 text-xs font-semibold rounded-full ${
                          driver.isOnline 
                            ? 'bg-green-100 text-green-800' 
                            : 'bg-gray-100 text-gray-800'
                        }`}>
                          {driver.isOnline ? '🟢 Active' : '⚪ Inactive'}
                        </span>
                        {driver.status && (
                          <span className={`ml-2 px-2 py-1 text-xs font-semibold rounded-full ${
                            driver.status === 'available' ? 'bg-blue-100 text-blue-800' :
                            driver.status === 'busy' ? 'bg-red-100 text-red-800' :
                            driver.status === 'on_break' ? 'bg-yellow-100 text-yellow-800' :
                            'bg-gray-100 text-gray-800'
                          }`}>
                            {driver.status.replace('_', ' ')}
                          </span>
                        )}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm">
                        <Link
                          href={`/drivers/edit/${driver.id}`}
                          className="text-blue-600 hover:text-blue-800 mr-3 font-medium"
                        >
                          Edit
                        </Link>
                        <button
                          onClick={() => handleDelete(driver.id, driver.name || 'Driver')}
                          className="text-red-600 hover:text-red-800 font-medium"
                        >
                          Delete
                        </button>
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  );
}