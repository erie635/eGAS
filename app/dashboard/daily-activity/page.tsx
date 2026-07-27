'use client';

import { useState, useEffect, useRef } from 'react';
import { db, auth } from '../../../lib/firebase';
import { collection, getDocs, query, where, orderBy, onSnapshot, doc, updateDoc, getDoc, setDoc, serverTimestamp } from 'firebase/firestore';
import Link from 'next/link';
import toast from 'react-hot-toast';

// Generate a unique driver ID
const generateDriverId = (driverName: string) => {
  const namePrefix = driverName.substring(0, 3).toUpperCase();
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  let randomPart = '';
  for (let i = 0; i < 6; i++) {
    randomPart += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  const timestamp = Date.now().toString();
  const timePart = timestamp.slice(-3);
  return `${namePrefix}${randomPart}${timePart}`;
};

interface DailyActivity {
  id: string;
  driverId: string;
  driverName: string;
  numberPlate?: string;
  date: string;
  isOnline: boolean;
  status: string;
  isAvailable: boolean;
  onlineStart?: any;
  offlineStart?: any;
  lastOnlineTime?: any;
  lastOfflineTime?: any;
  totalHours?: number;
  totalMinutesDisplay?: number;
  totalMinutes?: number;
  totalOfflineHours?: number;
  totalOfflineMinutes?: number;
  totalOfflineMinutesCumulative?: number;
  onlineSessions?: number;
  offlineSessions?: number;
  totalSwitches?: number;
  onlineHistory?: any[];
  offlineHistory?: any[];
  fuelAvailable?: string;
  hasFuel?: boolean;
  remainingFuel?: {
    Petrol: number;
    Diesel: number;
    Kerosene: number;
    'V-Power': number;
  };
  fuelUpdatedAt?: any;
  latitude?: number;
  longitude?: number;
  speed?: number;
  heading?: number;
  locationHistory?: any[];
  activeOrderId?: string | null;
  orderStartedAt?: any | null;
  currentClientName?: string | null;
  currentClientPhone?: string | null;
  currentClientLocation?: string | null;
  totalOrdersCompleted?: number;
  totalRevenueToday?: number;
  averageSessionDuration?: number;
  longestOnlineSession?: number;
  longestOfflineSession?: number;
  totalOnlineTimeToday?: number;
  totalOfflineTimeToday?: number;
  efficiency?: number;
  _refreshToken?: string;
  _forceRefresh?: any;
  _lastSync?: any;
  _adminCreated?: boolean;
  _createdBy?: string;
  _createdAt?: any;
  createdAt?: any;
  updatedAt?: any;
  dateOnly?: string;
  weekDay?: string;
  monthName?: string;
  year?: number;
  weekNumber?: number;
  lastUpdated?: any;
  _calculatedHours?: number;
  _calculatedMinutes?: number;
}

export default function DailyActivityPage() {
  const [activities, setActivities] = useState<DailyActivity[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [selectedDate, setSelectedDate] = useState<string>(() => {
    const today = new Date();
    return today.toISOString().split('T')[0];
  });
  const [searchTerm, setSearchTerm] = useState('');
  const [sortBy, setSortBy] = useState<'hours' | 'name' | 'offline'>('hours');
  const [indexError, setIndexError] = useState<string | null>(null);
  const [currentTime, setCurrentTime] = useState<Date>(new Date());
  const [userBackground, setUserBackground] = useState('white');
  const [lastRefreshTime, setLastRefreshTime] = useState<Date>(new Date());
  const [lastSyncTime, setLastSyncTime] = useState<Date>(new Date());
  
  // Use refs for component lifecycle management
  const isMountedRef = useRef(true);
  const unsubscribeRef = useRef<(() => void) | null>(null);
  const driverUnsubscribeRef = useRef<(() => void) | null>(null);
  const updateTimeoutRef = useRef<NodeJS.Timeout | null>(null);

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

  // Update current time every 5 seconds for real-time duration calculations
  useEffect(() => {
    const interval = setInterval(() => {
      if (isMountedRef.current) {
        setCurrentTime(new Date());
      }
    }, 5000);

    return () => {
      clearInterval(interval);
    };
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

  // Safe update function using setDoc with merge
  const safeUpdateOrCreateActivity = async (docId: string, updateData: any) => {
    try {
      const docRef = doc(db, 'driverDailyActivity', docId);
      // Use setDoc with merge to either create or update
      await setDoc(docRef, updateData, { merge: true });
      return true;
    } catch (error) {
      console.error('Error updating/creating document:', error);
      return false;
    }
  };

  // Calculate hours worked for a driver in real-time
  const calculateDriverHours = (activity: DailyActivity): { hours: number; minutes: number } => {
    let totalMinutes = 0;
    const now = currentTime;

    try {
      // If driver is currently online, calculate from onlineStart to now
      if (activity.isOnline && activity.onlineStart) {
        const start = activity.onlineStart.toDate ? activity.onlineStart.toDate() : new Date(activity.onlineStart);
        const diffMs = now.getTime() - start.getTime();
        if (diffMs > 0) {
          totalMinutes += Math.floor(diffMs / 60000);
        }
      }

      // Add any stored offline time (if available)
      if (activity.totalOfflineMinutesCumulative) {
        totalMinutes += activity.totalOfflineMinutesCumulative;
      }

      // If we have totalMinutes stored, use that as base
      if (activity.totalMinutes) {
        totalMinutes = Math.max(totalMinutes, activity.totalMinutes);
      }

      // If we have totalHours and totalMinutesDisplay stored, use those
      if (activity.totalHours !== undefined && activity.totalMinutesDisplay !== undefined) {
        const storedMinutes = (activity.totalHours * 60) + activity.totalMinutesDisplay;
        totalMinutes = Math.max(totalMinutes, storedMinutes);
      }

      const hours = Math.floor(totalMinutes / 60);
      const minutes = totalMinutes % 60;

      return { hours, minutes };
    } catch (error) {
      console.error('Error calculating driver hours:', error);
      return { hours: 0, minutes: 0 };
    }
  };

  // Helper function to safely get timestamp
  const getTimestamp = (value: any): Date | null => {
    if (!value) return null;
    try {
      if (value.toDate) {
        return value.toDate();
      }
      return new Date(value);
    } catch {
      return null;
    }
  };

  // Helper function to get server timestamp or current time
  const getServerTimestamp = () => {
    return serverTimestamp();
  };

  // Setup real-time driver status listener with server timestamps
  const setupDriverStatusListener = () => {
    if (driverUnsubscribeRef.current) {
      driverUnsubscribeRef.current();
      driverUnsubscribeRef.current = null;
    }

    // Listen to all drivers for real-time status changes
    const driversQuery = collection(db, 'drivers');
    
    driverUnsubscribeRef.current = onSnapshot(driversQuery, async (snapshot) => {
      // Skip if component unmounted
      if (!isMountedRef.current) return;

      const now = new Date();
      const todayStr = now.toISOString().split('T')[0];

      // Only process if we're looking at today's data
      if (selectedDate !== todayStr) return;

      // Load all today's activities once into a map
      const activityMap = new Map();
      try {
        const todayActivities = await getDocs(
          query(
            collection(db, 'driverDailyActivity'),
            where('date', '==', todayStr)
          )
        );
        todayActivities.forEach((docSnap) => {
          const data = docSnap.data();
          activityMap.set(data.driverId, {
            id: docSnap.id,
            ...data,
          });
        });
      } catch (error) {
        console.error('Error fetching today activities:', error);
        return;
      }

      let updatesFound = 0;
      const batchUpdates: { docId: string; data: any }[] = [];

      // Process each driver that changed
      for (const docChange of snapshot.docChanges()) {
        // Skip removed documents
        if (docChange.type === 'removed') {
          continue;
        }

        const driverData = docChange.doc.data();
        const driverId = docChange.doc.id;

        // Skip if driver has no name
        if (!driverData.name) continue;

        // Ensure isOnline is a boolean
        const isOnline = driverData.isOnline ?? false;

        // Use the cached activity map instead of querying
        const existingActivity = activityMap.get(driverId);

        // Build update data with only defined values
        const updateData: any = {
          driverId: driverId,
          driverName: driverData.name || 'Unknown',
          numberPlate: driverData.numberPlate || '',
          date: todayStr,
          isOnline: isOnline,
          status: driverData.status || 'offline',
          isAvailable: driverData.isAvailable ?? false,
          lastUpdated: getServerTimestamp(),
        };

        // Only set timestamps when status actually changes
        if (!existingActivity) {
          // First record ever - initialize timestamps with server timestamps
          if (isOnline) {
            updateData.onlineStart = getServerTimestamp();
            updateData.lastOnlineTime = getServerTimestamp();
            updateData.onlineSessions = 1;
            updateData.offlineSessions = 0;
          } else {
            updateData.offlineStart = getServerTimestamp();
            updateData.lastOfflineTime = getServerTimestamp();
            updateData.onlineSessions = 0;
            updateData.offlineSessions = 1;
          }
          updateData.totalSwitches = 0;
          updateData.totalHours = 0;
          updateData.totalMinutes = 0;
          updateData.totalMinutesDisplay = 0;
          updateData.createdAt = getServerTimestamp();

          batchUpdates.push({ docId: `${driverId}_${todayStr}`, data: updateData });
          updatesFound++;
        } else {
          // Use existingActivity data
          const current = existingActivity;

          // Only update timestamps if status actually changed
          if (current.isOnline !== isOnline) {
            if (isOnline) {
              // Driver went offline -> online
              updateData.onlineStart = getServerTimestamp();
              updateData.lastOnlineTime = getServerTimestamp();
              // Preserve offline start
              updateData.offlineStart = current.offlineStart || null;
              // Increment online sessions and switches
              updateData.onlineSessions = (current.onlineSessions || 0) + 1;
              updateData.totalSwitches = (current.totalSwitches || 0) + 1;
              // Preserve offline sessions
              updateData.offlineSessions = current.offlineSessions || 0;
            } else {
              // Driver went online -> offline
              // Calculate how long they were online
              if (current.onlineStart) {
                const start = getTimestamp(current.onlineStart);
                if (start) {
                  const nowDate = new Date();
                  const diffMs = nowDate.getTime() - start.getTime();
                  if (diffMs > 0) {
                    const minutesWorked = Math.floor(diffMs / 60000);
                    const currentTotalMinutes = (current.totalMinutes || 0) + minutesWorked;
                    updateData.totalMinutes = currentTotalMinutes;
                    updateData.totalHours = Math.floor(currentTotalMinutes / 60);
                    updateData.totalMinutesDisplay = currentTotalMinutes % 60;
                  }
                }
              }
              updateData.offlineStart = getServerTimestamp();
              updateData.lastOfflineTime = getServerTimestamp();
              // Preserve online start
              updateData.onlineStart = current.onlineStart || null;
              // Increment offline sessions and switches
              updateData.offlineSessions = (current.offlineSessions || 0) + 1;
              updateData.totalSwitches = (current.totalSwitches || 0) + 1;
              // Preserve online sessions
              updateData.onlineSessions = current.onlineSessions || 0;
            }
          } else {
            // Status didn't change - preserve existing timestamps
            updateData.onlineStart = current.onlineStart;
            updateData.offlineStart = current.offlineStart;
            updateData.onlineSessions = current.onlineSessions || 0;
            updateData.offlineSessions = current.offlineSessions || 0;
            updateData.totalSwitches = current.totalSwitches || 0;
            updateData.totalHours = current.totalHours || 0;
            updateData.totalMinutes = current.totalMinutes || 0;
            updateData.totalMinutesDisplay = current.totalMinutesDisplay || 0;
          }
        }

        // Only add location data if it exists and is not undefined or null
        if (driverData.latitude !== undefined && driverData.latitude !== null) {
          updateData.latitude = driverData.latitude;
        }
        if (driverData.longitude !== undefined && driverData.longitude !== null) {
          updateData.longitude = driverData.longitude;
        }
        if (driverData.speed !== undefined && driverData.speed !== null) {
          updateData.speed = driverData.speed;
        }
        if (driverData.heading !== undefined && driverData.heading !== null) {
          updateData.heading = driverData.heading;
        }

        // Only add fuel data if it exists
        if (driverData.remainingFuel) {
          updateData.remainingFuel = driverData.remainingFuel;
        }
        if (driverData.fuelAvailable) {
          updateData.fuelAvailable = driverData.fuelAvailable;
        }
        if (driverData.hasFuel !== undefined && driverData.hasFuel !== null) {
          updateData.hasFuel = driverData.hasFuel;
        }

        // Remove any undefined or null values from updateData
        Object.keys(updateData).forEach(key => {
          if (updateData[key] === undefined || updateData[key] === null) {
            delete updateData[key];
          }
        });

        if (existingActivity) {
          // Document exists - check for actual changes
          const docId = existingActivity.id;
          
          // Check for status changes
          const statusChanged = existingActivity.isOnline !== updateData.isOnline;
          
          // Check for other changes
          const hasChanges = statusChanged ||
            existingActivity.status !== updateData.status ||
            existingActivity.latitude !== updateData.latitude ||
            existingActivity.longitude !== updateData.longitude ||
            existingActivity.speed !== updateData.speed ||
            existingActivity.heading !== updateData.heading ||
            existingActivity.onlineSessions !== updateData.onlineSessions ||
            existingActivity.offlineSessions !== updateData.offlineSessions ||
            existingActivity.totalSwitches !== updateData.totalSwitches ||
            existingActivity.totalHours !== updateData.totalHours ||
            existingActivity.totalMinutesDisplay !== updateData.totalMinutesDisplay ||
            existingActivity.totalMinutes !== updateData.totalMinutes;

          if (statusChanged) {
            updatesFound++;
          }

          // Only write if something actually changed
          if (hasChanges) {
            batchUpdates.push({ docId, data: updateData });
          }
        } else {
          // Document doesn't exist - create it
          const docId = `${driverId}_${todayStr}`;
          batchUpdates.push({ docId, data: updateData });
          updatesFound++;
        }
      }

      // Process batch updates with throttling
      if (batchUpdates.length > 0) {
        // Clear any pending timeout
        if (updateTimeoutRef.current) {
          clearTimeout(updateTimeoutRef.current);
        }

        // Throttle updates to prevent excessive writes
        updateTimeoutRef.current = setTimeout(async () => {
          let successCount = 0;
          for (const batch of batchUpdates) {
            const success = await safeUpdateOrCreateActivity(batch.docId, batch.data);
            if (success) successCount++;
          }
          
          if (successCount > 0 && isMountedRef.current) {
            setLastSyncTime(new Date());
            setLastRefreshTime(new Date());
            console.log(`✅ Updated ${successCount} driver activities`);
          }
          
          updateTimeoutRef.current = null;
        }, 500); // 500ms throttle
      }

    }, (error) => {
      console.error('Error listening to driver status changes:', error);
      // Don't show toast for every error to avoid spam
    });
  };

  // Setup listener function for daily activities
  const setupListener = () => {
    if (unsubscribeRef.current) {
      unsubscribeRef.current();
      unsubscribeRef.current = null;
    }

    if (!selectedDate) return;

    const q = query(
      collection(db, 'driverDailyActivity'),
      where('date', '==', selectedDate)
    );

    unsubscribeRef.current = onSnapshot(q, async (snapshot) => {
      // Skip if component unmounted
      if (!isMountedRef.current) return;

      // ✅ FIX: Get all valid driver IDs from the drivers collection
      let validDriverIds = new Set<string>();
      try {
        const driversSnapshot = await getDocs(collection(db, 'drivers'));
        driversSnapshot.docs.forEach(doc => {
          validDriverIds.add(doc.id);
        });
      } catch (error) {
        console.error('Error fetching drivers for validation:', error);
        // If we can't fetch drivers, show all activities (fallback)
        validDriverIds = new Set();
      }

      const activitiesData = snapshot.docs.map(doc => {
        const data = doc.data();
        let customDriverId = data.driverId;
        if (!customDriverId || /^[a-zA-Z0-9]{20,}$/.test(customDriverId)) {
          customDriverId = data.driverName ? generateDriverId(data.driverName) : `DRV${Date.now().toString().slice(-6)}`;
        }
        return {
          id: doc.id,
          ...data,
          driverId: customDriverId,
          isOnline: data.isOnline ?? false,
          isAvailable: data.isAvailable ?? false,
        };
      }) as DailyActivity[];

      // ✅ FIX: Filter out activities for drivers that no longer exist
      let filteredActivitiesData = activitiesData;
      if (validDriverIds.size > 0) {
        filteredActivitiesData = activitiesData.filter(activity => {
          // Extract the actual driver ID from the activity document ID or driverId field
          const activityDocId = activity.id;
          const activityDriverId = activity.driverId;
          
          // Check if the driver ID exists in the valid driver IDs
          // The document ID format is usually `${driverId}_${date}`
          const extractedDriverId = activityDocId.split('_')[0];
          
          // Check if either the extracted ID or the driverId field exists in validDriverIds
          const isValid = validDriverIds.has(extractedDriverId) || validDriverIds.has(activityDriverId);
          
          if (!isValid) {
            console.log(`🗑️ Filtering out activity for deleted driver: ${activity.driverName} (${activityDriverId})`);
          }
          
          return isValid;
        });
      }

      const sortedData = filteredActivitiesData.sort((a, b) => {
        if (sortBy === 'hours') {
          return (b.totalHours || 0) - (a.totalHours || 0);
        }
        if (sortBy === 'offline') {
          return (b.totalOfflineHours || 0) - (a.totalOfflineHours || 0);
        }
        return a.driverName?.localeCompare(b.driverName || '') || 0;
      });

      setActivities(sortedData);
      setLoading(false);
      setIndexError(null);
      setLastRefreshTime(new Date());
      setLastSyncTime(new Date());
    }, (error) => {
      console.error('Error fetching daily activities:', error);
      if (error.code === 'failed-precondition' || error.message?.includes('index')) {
        const urlMatch = error.message?.match(/https:\/\/console\.firebase\.google\.com[^\s]*/);
        if (urlMatch) {
          setIndexError(urlMatch[0]);
        } else {
          setIndexError('https://console.firebase.google.com/v1/r/project/efilling-d1456/firestore/indexes?create_composite=Clpwcm9qZWN0cy9lZmlsbGluZy1kMTQ1Ni9kYXRhYmFzZXMvKGRlZmF1bHQpL2NvbGxlY3Rpb25Hcm91cHMvZHJpdmVyRGFpbHlBY3Rpdml0eS9pbmRleGVzL18QARoICgRkYXRlEAEaDgoKZHJpdmVyTmFtZRABGgwKCF9fbmFtZV9fEAE');
        }
      } else {
        // Only show toast for non-index errors to avoid spam
        if (!loading) {
          toast.error('Failed to load activities');
        }
      }
      setLoading(false);
    });
  };

  // Setup both listeners
  useEffect(() => {
    isMountedRef.current = true;
    setupListener();
    setupDriverStatusListener();

    return () => {
      isMountedRef.current = false;
      if (unsubscribeRef.current) {
        unsubscribeRef.current();
        unsubscribeRef.current = null;
      }
      if (driverUnsubscribeRef.current) {
        driverUnsubscribeRef.current();
        driverUnsubscribeRef.current = null;
      }
      if (updateTimeoutRef.current) {
        clearTimeout(updateTimeoutRef.current);
        updateTimeoutRef.current = null;
      }
    };
  }, [selectedDate, sortBy]);

  // Refresh data function
  const refreshData = async () => {
    if (refreshing) return;
    setRefreshing(true);
    setCurrentTime(new Date());

    try {
      // Re-establish the listener to get fresh data
      if (unsubscribeRef.current) {
        unsubscribeRef.current();
        unsubscribeRef.current = null;
      }

      // Small delay to ensure cleanup
      await new Promise(resolve => setTimeout(resolve, 200));

      // Re-setup the listener
      setupListener();

      // Also fetch fresh data directly
      const activityRef = collection(db, 'driverDailyActivity');
      const activityQuery = query(activityRef, where('date', '==', selectedDate));
      const activitySnapshot = await getDocs(activityQuery);

      // ✅ FIX: Get valid driver IDs
      let validDriverIds = new Set<string>();
      try {
        const driversSnapshot = await getDocs(collection(db, 'drivers'));
        driversSnapshot.docs.forEach(doc => {
          validDriverIds.add(doc.id);
        });
      } catch (error) {
        console.error('Error fetching drivers for validation:', error);
      }

      const activitiesData = activitySnapshot.docs.map(doc => {
        const data = doc.data();
        let customDriverId = data.driverId;
        if (!customDriverId || /^[a-zA-Z0-9]{20,}$/.test(customDriverId)) {
          customDriverId = data.driverName ? generateDriverId(data.driverName) : `DRV${Date.now().toString().slice(-6)}`;
        }
        return {
          id: doc.id,
          ...data,
          driverId: customDriverId,
          isOnline: data.isOnline ?? false,
          isAvailable: data.isAvailable ?? false,
        };
      }) as DailyActivity[];

      // ✅ FIX: Filter out activities for drivers that no longer exist
      let filteredActivitiesData = activitiesData;
      if (validDriverIds.size > 0) {
        filteredActivitiesData = activitiesData.filter(activity => {
          const activityDocId = activity.id;
          const activityDriverId = activity.driverId;
          const extractedDriverId = activityDocId.split('_')[0];
          return validDriverIds.has(extractedDriverId) || validDriverIds.has(activityDriverId);
        });
      }

      const sortedData = filteredActivitiesData.sort((a, b) => {
        if (sortBy === 'hours') {
          return (b.totalHours || 0) - (a.totalHours || 0);
        }
        if (sortBy === 'offline') {
          return (b.totalOfflineHours || 0) - (a.totalOfflineHours || 0);
        }
        return a.driverName?.localeCompare(b.driverName || '') || 0;
      });

      setActivities(sortedData);
      setLastRefreshTime(new Date());
      setLastSyncTime(new Date());
      toast.success('✅ Data refreshed successfully!');
    } catch (error) {
      console.error('Error refreshing data:', error);
      toast.error('Failed to refresh data. Retrying...');
      // Retry with re-setup
      setTimeout(() => {
        setupListener();
      }, 500);
    } finally {
      setRefreshing(false);
    }
  };

  // Get date range (last 7 days)
  const getDateRange = () => {
    const dates = [];
    for (let i = 0; i < 7; i++) {
      const date = new Date();
      date.setDate(date.getDate() - i);
      dates.push(date.toISOString().split('T')[0]);
    }
    return dates;
  };

  const formatTime = (timestamp: any): string => {
    if (!timestamp) return 'N/A';
    try {
      const date = timestamp.toDate ? timestamp.toDate() : new Date(timestamp);
      return date.toLocaleTimeString();
    } catch {
      return 'N/A';
    }
  };

  const formatDate = (dateStr: string): string => {
    const date = new Date(dateStr + 'T00:00:00');
    return date.toLocaleDateString('en-US', {
      weekday: 'short',
      month: 'short',
      day: 'numeric',
      year: 'numeric'
    });
  };

  // Calculate duration between two timestamps
  const calculateDuration = (startTime: any, endTime: Date = currentTime): string => {
    if (!startTime) return 'N/A';
    try {
      const start = startTime.toDate ? startTime.toDate() : new Date(startTime);
      const diffMs = endTime.getTime() - start.getTime();
      if (diffMs < 0) return 'N/A';
      const diffMins = Math.floor(diffMs / 60000);
      const hours = Math.floor(diffMins / 60);
      const minutes = diffMins % 60;
      if (hours > 0) {
        return `${hours}h ${minutes}m`;
      }
      return `${minutes}m`;
    } catch {
      return 'N/A';
    }
  };

  // Calculate offline duration accurately
  const calculateOfflineDuration = (activity: DailyActivity): string => {
    if (!activity.isOnline && activity.offlineStart) {
      return calculateDuration(activity.offlineStart);
    }
    if (activity.totalOfflineHours !== undefined && activity.totalOfflineHours !== null) {
      const hours = activity.totalOfflineHours;
      const minutes = activity.totalOfflineMinutes || 0;
      return `${hours}h ${minutes}m`;
    }
    return '0h 0m';
  };

  const getStatusBadge = (isOnline: boolean) => {
    if (isOnline) {
      return (
        <span className="px-2 py-1 text-xs font-semibold rounded-full bg-green-100 text-green-800 animate-pulse">
          🟢 Online
        </span>
      );
    }
    return (
      <span className="px-2 py-1 text-xs font-semibold rounded-full bg-red-100 text-red-800">
        🔴 Offline
      </span>
    );
  };

  // Calculate total hours for display - using real-time calculation
  const calculateTotalHoursForDisplay = (activity: DailyActivity): string => {
    const { hours, minutes } = calculateDriverHours(activity);
    return `${hours}h ${minutes}m`;
  };

  const getStatusDetails = (activity: DailyActivity): { status: string, duration: string, startTime: string } => {
    if (activity.isOnline && activity.onlineStart) {
      const duration = calculateDuration(activity.onlineStart);
      return {
        status: 'Online',
        duration: duration,
        startTime: formatTime(activity.onlineStart)
      };
    } else if (!activity.isOnline && activity.offlineStart) {
      const duration = calculateDuration(activity.offlineStart);
      return {
        status: 'Offline',
        duration: duration,
        startTime: formatTime(activity.offlineStart)
      };
    }
    return {
      status: 'Unknown',
      duration: 'N/A',
      startTime: 'N/A'
    };
  };

  const filteredActivities = activities
    .filter(activity =>
      activity.driverName?.toLowerCase().includes(searchTerm.toLowerCase()) ||
      activity.driverId?.toLowerCase().includes(searchTerm.toLowerCase()) ||
      activity.numberPlate?.toLowerCase().includes(searchTerm.toLowerCase())
    );

  const totalDrivers = filteredActivities.length;
  const onlineDrivers = filteredActivities.filter(a => a.isOnline).length;
  const offlineDrivers = totalDrivers - onlineDrivers;

  // REAL-TIME: Calculate total hours including minutes from all drivers
  const totalMinutesWorked = filteredActivities.reduce((sum, a) => {
    const { hours, minutes } = calculateDriverHours(a);
    return sum + (hours * 60) + minutes;
  }, 0);
  const totalHoursWorked = Math.floor(totalMinutesWorked / 60);
  const remainingMinutesWorked = totalMinutesWorked % 60;

  // REAL-TIME: Calculate average including minutes
  const averageMinutes = totalDrivers > 0 ? Math.floor(totalMinutesWorked / totalDrivers) : 0;
  const avgHours = Math.floor(averageMinutes / 60);
  const avgMinutes = averageMinutes % 60;

  if (indexError) {
    return (
      <div className={`space-y-6 ${getBackgroundClass()}`}>
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <div>
            <h1 className={`text-2xl font-bold ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'}`}>Daily Driver Activity</h1>
            <p className={`text-sm ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>View daily performance and activity of all drivers</p>
          </div>
          <Link href="/dashboard" className="bg-gray-500 hover:bg-gray-600 text-white px-4 py-2 rounded-lg text-sm font-medium transition">
            Back to Dashboard
          </Link>
        </div>
        <div className="bg-yellow-50 border border-yellow-200 rounded-xl p-6">
          <div className="flex items-start gap-4">
            <div className="text-2xl">⚠️</div>
            <div>
              <h3 className="text-lg font-semibold text-yellow-800">Index Required</h3>
              <p className="text-yellow-700 mt-1">
                Firestore needs an index to query driver activities. Click the button below to create it.
              </p>
              <a
                href={indexError}
                target="_blank"
                rel="noopener noreferrer"
                className="inline-block mt-4 px-6 py-2 bg-yellow-600 hover:bg-yellow-700 text-white rounded-lg font-medium transition"
              >
                Create Index in Firebase Console
              </a>
              <p className="text-sm text-yellow-600 mt-3">
                After creating the index, wait a few minutes for it to build, then refresh this page.
              </p>
            </div>
          </div>
        </div>
      </div>
    );
  }

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
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <div>
            <h1 className={`text-2xl font-bold ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'}`}>Daily Driver Activity</h1>
            <p className={`text-sm ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>View daily performance and activity of all drivers</p>
            <div className="flex items-center gap-3 mt-1">
              <p className={`text-xs ${userBackground === 'dark' ? 'text-gray-500' : 'text-gray-400'}`}>
                Last refreshed: {lastRefreshTime.toLocaleTimeString()}
              </p>
              <span className="text-xs text-green-500">
                🟢 Last Sync: {lastSyncTime.toLocaleTimeString()}
              </span>
              <span className="text-xs text-blue-500 animate-pulse">
                🔄 Real-time
              </span>
            </div>
          </div>
          <div className="flex gap-2">
            <button
              onClick={refreshData}
              disabled={refreshing}
              className={`flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium transition ${
                refreshing
                  ? 'bg-gray-400 cursor-not-allowed text-white'
                  : 'bg-blue-500 hover:bg-blue-600 text-white'
              }`}
            >
              {refreshing ? (
                <>
                  <svg className="animate-spin h-4 w-4 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                  </svg>
                  Refreshing...
                </>
              ) : (
                <>
                  <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
                  </svg>
                  Refresh Data
                </>
              )}
            </button>
            <Link href="/dashboard" className="bg-gray-500 hover:bg-gray-600 text-white px-4 py-2 rounded-lg text-sm font-medium transition">
              Back to Dashboard
            </Link>
          </div>
        </div>

        {/* Real-time Status Indicator */}
        <div className={`rounded-xl p-3 flex items-center justify-between ${userBackground === 'dark' ? 'bg-blue-900/30 border border-blue-700 text-blue-200' : 'bg-blue-50 border border-blue-200 text-blue-700'}`}>
          <div className="flex items-center gap-2">
            <div className={`w-2 h-2 rounded-full ${refreshing ? 'bg-yellow-500 animate-pulse' : 'bg-green-500 animate-pulse'}`}></div>
            <span className={`text-sm ${userBackground === 'dark' ? 'text-blue-300' : 'text-blue-700'}`}>
              {refreshing ? '🔄 Refreshing data...' : '✅ Live updates: Driver status auto-syncs from database'}
            </span>
          </div>
          <span className={`text-xs ${userBackground === 'dark' ? 'text-blue-300' : 'text-blue-600'}`}>
            {onlineDrivers} online • {offlineDrivers} offline
          </span>
        </div>

        {/* Filters and Stats */}
        <div className="grid grid-cols-1 md:grid-cols-5 gap-4">
          <div className="rounded-xl shadow-sm p-4 border bg-cyan-300 border-blue-200">
            <p className="text-sm text-gray-800">Date</p>
            <select
              value={selectedDate}
              onChange={(e) => setSelectedDate(e.target.value)}
              className="mt-1 w-full px-3 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500 bg-gray-400 border-gray-300"
            >
              {getDateRange().map(date => (
                <option key={date} value={date}>
                  {formatDate(date)}
                </option>
              ))}
            </select>
          </div>
          <div className="rounded-xl shadow-sm p-4 border bg-green-50 border-green-200">
            <p className="text-sm text-gray-800">Total Drivers</p>
            <p className="text-2xl font-bold text-gray-900">{totalDrivers}</p>
          </div>
          <div className="rounded-xl shadow-sm p-4 border bg-green-100 border-green-300">
            <p className="text-sm text-gray-800">Online Now</p>
            <p className="text-2xl font-bold text-green-600">{onlineDrivers}</p>
          </div>
          <div className="rounded-xl shadow-sm p-4 border bg-red-200 border-red-200">
            <p className="text-sm text-gray-800">Offline Now</p>
            <p className="text-2xl font-bold text-red-600">{offlineDrivers}</p>
          </div>
          <div className="rounded-xl shadow-sm p-4 border bg-blue-300 border-blue-200">
            <p className="text-sm text-gray-800">Average Working Time</p>
            <p className="text-2xl font-bold text-blue-600">
              {avgHours}h {avgMinutes}m
            </p>
          </div>
        </div>

        {/* Search and Sort */}
        <div className="rounded-xl shadow-sm p-4 border bg-gray-50 border-gray-200">
          <div className="flex flex-col sm:flex-row gap-4">
            <input
              type="text"
              placeholder="Search by driver name, ID or plate number..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="flex-1 px-4 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500 bg-gray-200 border-gray-300"
            />
            <select
              value={sortBy}
              onChange={(e) => setSortBy(e.target.value as 'hours' | 'name' | 'offline')}
              className="px-4 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500 bg-gray-400 border-gray-300"
            >
              <option value="hours">Sort by Hours Worked</option>
              <option value="offline">Sort by Offline Hours</option>
              <option value="name">Sort by Name</option>
            </select>
          </div>
        </div>

        {/* Activity Table */}
        <div className={`rounded-xl shadow-sm border overflow-hidden ${userBackground === 'dark' ? 'border-gray-700' : 'border-gray-100'} ${getCardClass()}`}>
          <div className={`p-6 border-b ${userBackground === 'dark' ? 'border-gray-700' : 'border-gray-200'} flex justify-between items-center`}>
            <h2 className={`text-lg font-semibold ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'}`}>Driver Activity - {formatDate(selectedDate)}</h2>
            <span className={`text-sm ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>{filteredActivities.length} drivers</span>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead className={userBackground === 'dark' ? 'bg-gray-800' : 'bg-gray-600'}>
                <tr>
                  <th className={`px-6 py-3 text-left text-xs font-medium uppercase tracking-wider ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-200'}`}>Driver</th>
                  <th className={`px-6 py-3 text-left text-xs font-medium uppercase tracking-wider ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-200'}`}>Driver ID</th>
                  <th className={`px-6 py-3 text-left text-xs font-medium uppercase tracking-wider ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-200'}`}>Plate Number</th>
                  <th className={`px-6 py-3 text-left text-xs font-medium uppercase tracking-wider ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-200'}`}>Status</th>
                  <th className={`px-6 py-3 text-left text-xs font-medium uppercase tracking-wider ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-200'}`}>Current Duration</th>
                  <th className={`px-6 py-3 text-left text-xs font-medium uppercase tracking-wider ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-200'}`}>Offline Duration</th>
                  <th className={`px-6 py-3 text-left text-xs font-medium uppercase tracking-wider ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-200'}`}>Sessions</th>
                  <th className={`px-6 py-3 text-left text-xs font-medium uppercase tracking-wider ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-200'}`}>Times</th>
                  <th className={`px-6 py-3 text-left text-xs font-medium uppercase tracking-wider ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-200'}`}>Total Hours</th>
                  <th className={`px-6 py-3 text-left text-xs font-medium uppercase tracking-wider ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-200'}`}>Efficiency</th>
                  <th className={`px-6 py-3 text-left text-xs font-medium uppercase tracking-wider ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-200'}`}>Last Updated</th>
                </tr>
              </thead>
              <tbody className={`divide-y ${userBackground === 'dark' ? 'divide-gray-700' : 'divide-gray-200'}`}>
                {filteredActivities.length === 0 ? (
                  <tr>
                    <td colSpan={11} className={`px-6 py-8 text-center ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>
                      No activity records found for this date
                    </td>
                  </tr>
                ) : (
                  filteredActivities.map((activity) => {
                    const statusInfo = getStatusDetails(activity);
                    const offlineDuration = calculateOfflineDuration(activity);
                    const efficiency = activity.efficiency || 0;
                    const onlineSessions = activity.onlineSessions || 0;
                    const offlineSessions = activity.offlineSessions || 0;
                    const totalSwitches = activity.totalSwitches || 0;
                    const totalHoursDisplay = calculateTotalHoursForDisplay(activity);
                    return (
                      <tr key={activity.id} className={userBackground === 'dark' ? 'hover:bg-gray-800/50' : 'hover:bg-gray-50'}>
                        <td className="px-6 py-4 whitespace-nowrap">
                          <div className="flex items-center">
                            <div className="relative">
                              <div className="w-8 h-8 rounded-full bg-green-100 flex items-center justify-center text-green-600 font-semibold text-sm">
                                {activity.driverName?.charAt(0) || '?'}
                              </div>
                              {activity.isOnline && (
                                <div className="absolute -bottom-1 -right-1 w-3 h-3 bg-green-500 rounded-full border-2 border-white animate-pulse"></div>
                              )}
                              {!activity.isOnline && (
                                <div className="absolute -bottom-1 -right-1 w-3 h-3 bg-red-500 rounded-full border-2 border-white"></div>
                              )}
                            </div>
                            <div className="ml-3">
                              <div className={`text-sm font-medium ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'}`}>{activity.driverName || 'Unknown'}</div>
                            </div>
                          </div>
                        </td>
                        <td className="px-6 py-4 whitespace-nowrap">
                          <span className="text-sm font-mono font-medium text-blue-600 bg-blue-50 px-2 py-1 rounded">
                            {activity.driverId || 'N/A'}
                          </span>
                        </td>
                        <td className="px-6 py-4 whitespace-nowrap">
                          <span className={`text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'}`}>
                            {activity.numberPlate || 'N/A'}
                          </span>
                        </td>
                        <td className="px-6 py-4 whitespace-nowrap">
                          {getStatusBadge(activity.isOnline)}
                        </td>
                        <td className="px-6 py-4 whitespace-nowrap">
                          <span className={`text-sm font-semibold ${activity.isOnline ? 'text-green-600' : 'text-red-600'}`}>
                            {statusInfo.duration}
                          </span>
                        </td>
                        <td className="px-6 py-4 whitespace-nowrap">
                          <span className="text-sm font-semibold text-red-600">
                            {offlineDuration}
                          </span>
                        </td>
                        <td className="px-6 py-4 whitespace-nowrap">
                          <div className="flex flex-col space-y-1">
                            <span className={`text-xs ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-600'}`}>
                              Online: {onlineSessions}
                            </span>
                            <span className={`text-xs ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-600'}`}>
                              Offline: {offlineSessions}
                            </span>
                            <span className={`text-xs ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-400'}`}>
                              Switches: {totalSwitches}
                            </span>
                          </div>
                        </td>
                        <td className="px-6 py-4 whitespace-nowrap">
                          <div className="flex flex-col space-y-1">
                            {activity.isOnline ? (
                              <>
                                <span className="text-xs text-green-600 font-medium">
                                  Online since: {formatTime(activity.onlineStart)}
                                </span>
                                {activity.offlineStart && (
                                  <span className={`text-xs ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-400'}`}>
                                    Last offline: {formatTime(activity.offlineStart)}
                                  </span>
                                )}
                              </>
                            ) : (
                              <>
                                <span className="text-xs text-red-600 font-medium">
                                  Offline since: {formatTime(activity.offlineStart)}
                                </span>
                                {activity.onlineStart && (
                                  <span className={`text-xs ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-400'}`}>
                                    Last online: {formatTime(activity.onlineStart)}
                                  </span>
                                )}
                              </>
                            )}
                            {!activity.onlineStart && !activity.offlineStart && (
                              <span className={`text-xs ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>No activity recorded</span>
                            )}
                          </div>
                        </td>
                        <td className="px-6 py-4 whitespace-nowrap">
                          <span className="text-lg font-bold text-green-700">
                            {totalHoursDisplay}
                          </span>
                        </td>
                        <td className="px-6 py-4 whitespace-nowrap">
                          <div className="flex items-center gap-2">
                            <div className="w-16 bg-gray-200 rounded-full h-2">
                              <div
                                className="bg-blue-500 rounded-full h-2"
                                style={{ width: `${Math.min(efficiency, 100)}%` }}
                              ></div>
                            </div>
                            <span className={`text-sm font-medium ${userBackground === 'dark' ? 'text-white' : 'text-gray-700'}`}>
                              {efficiency.toFixed(0)}%
                            </span>
                          </div>
                        </td>
                        <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                          {activity.lastUpdated ? formatTime(activity.lastUpdated) : 'N/A'}
                        </td>
                      </tr>
                    );
                  })
                )}
              </tbody>
            </table>
          </div>
        </div>

        {/* Summary Footer */}
        <div className={`rounded-xl shadow-sm p-4 border ${userBackground === 'dark' ? 'border-gray-700' : 'border-gray-100'} ${getCardClass()}`}>
          <div className="grid grid-cols-2 md:grid-cols-6 gap-4 bg-cyan-500 text-center">
            <div>
              <p className={`text-sm ${userBackground === 'dark' ? 'text-gray-900' : 'text-gray-800'}`}>Total Hours Worked</p>
              <p className={`text-xl font-bold ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'}`}>
                {totalHoursWorked}h {remainingMinutesWorked}m
              </p>
            </div>
            <div>
              <p className={`text-sm ${userBackground === 'dark' ? 'text-gray-900' : 'text-gray-800'}`}>Online Drivers</p>
              <p className="text-xl font-bold text-green-600">{onlineDrivers}</p>
            </div>
            <div>
              <p className={`text-sm ${userBackground === 'dark' ? 'text-gray-900' : 'text-gray-800'}`}>Offline Drivers</p>
              <p className="text-xl font-bold text-red-600">{offlineDrivers}</p>
            </div>
            <div>
              <p className={`text-sm ${userBackground === 'dark' ? 'text-gray-900' : 'text-gray-800'}`}>Average Working Time</p>
              <p className={`text-xl font-bold ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'}`}>
                {avgHours}h {avgMinutes}m
              </p>
            </div>
            <div>
              <p className={`text-sm ${userBackground === 'dark' ? 'text-gray-900' : 'text-gray-800'}`}>Total Sessions</p>
              <p className={`text-xl font-bold ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'}`}>
                {filteredActivities.reduce((sum, a) => sum + (a.onlineSessions || 0) + (a.offlineSessions || 0), 0)}
              </p>
            </div>
            <div>
              <p className={`text-sm ${userBackground === 'dark' ? 'text-gray-900' : 'text-gray-800'}`}>Last Sync</p>
              <p className={`text-xl font-bold ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'}`}>
                {lastSyncTime.toLocaleTimeString()}
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}