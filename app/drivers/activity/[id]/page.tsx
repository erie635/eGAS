'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { db } from '../../../../lib/firebase';
import { doc, getDoc, collection, query, where, getDocs } from 'firebase/firestore';
import toast from 'react-hot-toast';

export default function DriverActivityPage({ params }: { params: { id: string } }) {
  const router = useRouter();
  const [loading, setLoading] = useState(true);
  const [driver, setDriver] = useState<any>(null);
  const [activityData, setActivityData] = useState({
    today: { online: 0, offline: 0, totalOnlineMinutes: 0, totalOfflineMinutes: 0 },
    week: { online: 0, offline: 0, totalOnlineMinutes: 0, totalOfflineMinutes: 0 },
    month: { online: 0, offline: 0, totalOnlineMinutes: 0, totalOfflineMinutes: 0 }
  });

  useEffect(() => {
    fetchDriverActivity();
  }, [params.id]);

  const calculateTimeBetween = (startTime: string, endTime: string) => {
    const start = new Date(startTime);
    const end = new Date(endTime);
    return Math.floor((end.getTime() - start.getTime()) / 60000); // minutes
  };

  const calculateActivity = (history: any[], period: 'today' | 'week' | 'month') => {
    const now = new Date();
    let periodStart = new Date();
    
    if (period === 'today') {
      periodStart = new Date(now.setHours(0, 0, 0, 0));
    } else if (period === 'week') {
      periodStart = new Date(now);
      periodStart.setDate(periodStart.getDate() - 7);
    } else {
      periodStart = new Date(now);
      periodStart.setDate(periodStart.getDate() - 30);
    }

    let onlineCount = 0;
    let offlineCount = 0;
    let totalOnlineMinutes = 0;
    let totalOfflineMinutes = 0;

    for (let i = 0; i < history.length - 1; i++) {
      const current = new Date(history[i].timestamp);
      const next = new Date(history[i + 1].timestamp);
      
      if (current >= periodStart) {
        const diffMinutes = Math.floor((next.getTime() - current.getTime()) / 60000);
        
        if (history[i].status === 'online') {
          onlineCount++;
          totalOnlineMinutes += diffMinutes;
        } else {
          offlineCount++;
          totalOfflineMinutes += diffMinutes;
        }
      }
    }

    return { onlineCount, offlineCount, totalOnlineMinutes, totalOfflineMinutes };
  };

  const fetchDriverActivity = async () => {
    try {
      const docRef = doc(db, 'drivers', params.id);
      const docSnap = await getDoc(docRef);
      
      if (docSnap.exists()) {
        const data = docSnap.data();
        setDriver(data);

        // Combine all history
        const allHistory = [
          ...(data.onlineHistory || []).map(h => ({ ...h, status: 'online' })),
          ...(data.offlineHistory || []).map(h => ({ ...h, status: 'offline' }))
        ].sort((a, b) => new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime());

        // Calculate for different periods
        const today = calculateActivity(allHistory, 'today');
        const week = calculateActivity(allHistory, 'week');
        const month = calculateActivity(allHistory, 'month');

        setActivityData({
          today,
          week,
          month
        });
      } else {
        toast.error('Driver not found');
        router.push('/drivers');
      }
    } catch (error) {
      console.error('Error fetching driver activity:', error);
      toast.error('Failed to load driver activity');
    } finally {
      setLoading(false);
    }
  };

  const formatDuration = (minutes: number) => {
    if (minutes < 60) return `${minutes}m`;
    const hours = Math.floor(minutes / 60);
    const mins = minutes % 60;
    return `${hours}h ${mins}m`;
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-green-500"></div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Driver Activity</h1>
          <p className="text-sm text-gray-500">
            {driver?.name} - Online/Offline Activity Tracking
          </p>
        </div>
        <div className="flex space-x-3">
          <Link 
            href={`/drivers/edit/${params.id}`}
            className="text-sm text-blue-600 hover:text-blue-800 flex items-center space-x-1"
          >
            <span>✏️</span>
            <span>Edit Driver</span>
          </Link>
          <Link 
            href="/drivers" 
            className="text-sm text-gray-500 hover:text-gray-700 flex items-center space-x-1"
          >
            <span>←</span>
            <span>Back to Drivers</span>
          </Link>
        </div>
      </div>

      {/* Current Status */}
      <div className="bg-white rounded-xl shadow-sm p-6 border border-gray-100">
        <div className="flex items-center justify-between">
          <div className="flex items-center space-x-4">
            <div className={`w-4 h-4 rounded-full ${driver?.isOnline ? 'bg-green-500 animate-pulse' : 'bg-gray-400'}`}></div>
            <div>
              <h2 className="text-lg font-semibold">
                {driver?.isOnline ? '🟢 Online' : '⚪ Offline'}
              </h2>
              <p className="text-sm text-gray-500">
                Status: {driver?.status || 'Unknown'}
              </p>
            </div>
          </div>
          <div className="text-right">
            <p className="text-sm text-gray-500">Last Update</p>
            <p className="text-sm font-medium">
              {driver?.lastUpdate ? new Date(driver.lastUpdate).toLocaleString() : 'Never'}
            </p>
          </div>
        </div>
      </div>

      {/* Activity Summary Cards */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        {/* Today */}
        <div className="bg-white rounded-xl shadow-sm p-6 border border-gray-100">
          <h3 className="text-sm font-medium text-gray-500 mb-4">Today</h3>
          <div className="space-y-3">
            <div className="flex justify-between">
              <span className="text-sm text-gray-600">🟢 Online</span>
              <span className="text-sm font-medium text-green-600">
                {activityData.today.onlineCount} times
              </span>
            </div>
            <div className="flex justify-between">
              <span className="text-sm text-gray-600">⚪ Offline</span>
              <span className="text-sm font-medium text-red-600">
                {activityData.today.offlineCount} times
              </span>
            </div>
            <div className="flex justify-between border-t pt-2">
              <span className="text-sm font-medium text-gray-700">Total Online</span>
              <span className="text-sm font-bold text-green-600">
                {formatDuration(activityData.today.totalOnlineMinutes)}
              </span>
            </div>
            <div className="flex justify-between">
              <span className="text-sm font-medium text-gray-700">Total Offline</span>
              <span className="text-sm font-bold text-red-600">
                {formatDuration(activityData.today.totalOfflineMinutes)}
              </span>
            </div>
          </div>
        </div>

        {/* This Week */}
        <div className="bg-white rounded-xl shadow-sm p-6 border border-gray-100">
          <h3 className="text-sm font-medium text-gray-500 mb-4">This Week</h3>
          <div className="space-y-3">
            <div className="flex justify-between">
              <span className="text-sm text-gray-600">🟢 Online</span>
              <span className="text-sm font-medium text-green-600">
                {activityData.week.onlineCount} times
              </span>
            </div>
            <div className="flex justify-between">
              <span className="text-sm text-gray-600">⚪ Offline</span>
              <span className="text-sm font-medium text-red-600">
                {activityData.week.offlineCount} times
              </span>
            </div>
            <div className="flex justify-between border-t pt-2">
              <span className="text-sm font-medium text-gray-700">Total Online</span>
              <span className="text-sm font-bold text-green-600">
                {formatDuration(activityData.week.totalOnlineMinutes)}
              </span>
            </div>
            <div className="flex justify-between">
              <span className="text-sm font-medium text-gray-700">Total Offline</span>
              <span className="text-sm font-bold text-red-600">
                {formatDuration(activityData.week.totalOfflineMinutes)}
              </span>
            </div>
          </div>
        </div>

        {/* This Month */}
        <div className="bg-white rounded-xl shadow-sm p-6 border border-gray-100">
          <h3 className="text-sm font-medium text-gray-500 mb-4">This Month</h3>
          <div className="space-y-3">
            <div className="flex justify-between">
              <span className="text-sm text-gray-600">🟢 Online</span>
              <span className="text-sm font-medium text-green-600">
                {activityData.month.onlineCount} times
              </span>
            </div>
            <div className="flex justify-between">
              <span className="text-sm text-gray-600">⚪ Offline</span>
              <span className="text-sm font-medium text-red-600">
                {activityData.month.offlineCount} times
              </span>
            </div>
            <div className="flex justify-between border-t pt-2">
              <span className="text-sm font-medium text-gray-700">Total Online</span>
              <span className="text-sm font-bold text-green-600">
                {formatDuration(activityData.month.totalOnlineMinutes)}
              </span>
            </div>
            <div className="flex justify-between">
              <span className="text-sm font-medium text-gray-700">Total Offline</span>
              <span className="text-sm font-bold text-red-600">
                {formatDuration(activityData.month.totalOfflineMinutes)}
              </span>
            </div>
          </div>
        </div>
      </div>

      {/* Detailed Activity History */}
      <div className="bg-white rounded-xl shadow-sm border border-gray-100">
        <div className="p-6 border-b border-gray-200">
          <h3 className="text-lg font-semibold text-gray-900">Detailed Activity History</h3>
          <p className="text-sm text-gray-500">All online/offline events in chronological order</p>
        </div>
        <div className="p-6">
          <div className="max-h-96 overflow-y-auto">
            {[...(driver?.onlineHistory || []), ...(driver?.offlineHistory || [])]
              .sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime())
              .slice(0, 50)
              .map((entry, index) => (
                <div key={index} className="flex items-center justify-between py-3 border-b border-gray-100">
                  <div className="flex items-center space-x-3">
                    <span className={entry.status === 'online' ? 'text-green-500' : 'text-red-500'}>
                      {entry.status === 'online' ? '🟢' : '⚪'}
                    </span>
                    <span className="text-sm font-medium">
                      {entry.status === 'online' ? 'Went Online' : 'Went Offline'}
                    </span>
                  </div>
                  <div className="text-sm text-gray-500">
                    {entry.date} at {entry.time}
                  </div>
                </div>
              ))}
            {(!driver?.onlineHistory || driver.onlineHistory.length === 0) && 
             (!driver?.offlineHistory || driver.offlineHistory.length === 0) && (
              <p className="text-center text-gray-500 py-8">No activity recorded yet</p>
            )}
          </div>
        </div>
      </div>

      {/* Quick Actions */}
      <div className="flex justify-end space-x-3">
        <Link
          href={`/drivers/edit/${params.id}`}
          className="px-4 py-2 text-sm font-medium text-white bg-blue-500 rounded-lg hover:bg-blue-600 transition"
        >
          Edit Driver
        </Link>
        <Link
          href="/drivers"
          className="px-4 py-2 text-sm font-medium text-gray-700 bg-gray-100 rounded-lg hover:bg-gray-200 transition"
        >
          Back to List
        </Link>
      </div>
    </div>
  );
}