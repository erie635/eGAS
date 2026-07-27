'use client';

import { useState, useEffect, useCallback, useRef } from 'react';
import { db, auth } from '../../../lib/firebase';
import { 
  collection, doc, updateDoc, onSnapshot, addDoc, 
  serverTimestamp, query, where, getDocs, arrayUnion,
  setDoc, getDoc, orderBy, limit
} from 'firebase/firestore';
import toast from 'react-hot-toast';
import Link from 'next/link';

export default function UpdateFuel() {
  const [drivers, setDrivers] = useState([]);
  const [selectedDriverId, setSelectedDriverId] = useState('');
  const [loading, setLoading] = useState(false);
  const [fuelData, setFuelData] = useState({
    Petrol: 0,
    Diesel: 0,
    Kerosene: 0,
    'V-Power': 0
  });
  const [previousFuelData, setPreviousFuelData] = useState({
    Petrol: 0,
    Diesel: 0,
    Kerosene: 0,
    'V-Power': 0
  });
  const [fuelHistory, setFuelHistory] = useState([]);
  const [showHistory, setShowHistory] = useState(false);
  const [showCreateDriver, setShowCreateDriver] = useState(false);
  const [createLoading, setCreateLoading] = useState(false);
  const [selectedDriverName, setSelectedDriverName] = useState('');
  const [dateFilter, setDateFilter] = useState('');
  const [dateFilteredHistory, setDateFilteredHistory] = useState([]);
  const [showDateFilterModal, setShowDateFilterModal] = useState(false);
  const [isFiltering, setIsFiltering] = useState(false);
  const [userBackground, setUserBackground] = useState('white');
  
  const isSelectingRef = useRef(false);
  const lastSelectedIdRef = useRef('');
  
  const [newDriver, setNewDriver] = useState({
    name: '',
    email: '',
    phone: '',
    petrol: 0,
    diesel: 0,
    kerosene: 0,
    vpower: 0,
    vehicleType: 'Pending Assignment',
    numberPlate: 'Pending Assignment'
  });

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

  // Listen for real-time driver updates
  useEffect(() => {
    const unsubscribe = onSnapshot(collection(db, 'drivers'), (snapshot) => {
      const driversData = snapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data()
      }));
      setDrivers(driversData);
      
      if (selectedDriverId && !isSelectingRef.current) {
        const updatedDriver = driversData.find(d => d.id === selectedDriverId);
        if (updatedDriver && updatedDriver.remainingFuel) {
          const currentFuel = {
            Petrol: Number(updatedDriver.remainingFuel.Petrol) || 0,
            Diesel: Number(updatedDriver.remainingFuel.Diesel) || 0,
            Kerosene: Number(updatedDriver.remainingFuel.Kerosene) || 0,
            'V-Power': Number(updatedDriver.remainingFuel['V-Power']) || 0
          };
          setFuelData(currentFuel);
          setPreviousFuelData(currentFuel);
          setSelectedDriverName(updatedDriver.name || '');
        }
      }
    });

    return () => unsubscribe();
  }, [selectedDriverId]);

  const handleDriverSelect = useCallback((driverId) => {
    if (!driverId) {
      setSelectedDriverId('');
      setFuelData({ Petrol: 0, Diesel: 0, Kerosene: 0, 'V-Power': 0 });
      setPreviousFuelData({ Petrol: 0, Diesel: 0, Kerosene: 0, 'V-Power': 0 });
      setSelectedDriverName('');
      return;
    }

    if (driverId === lastSelectedIdRef.current) {
      return;
    }

    isSelectingRef.current = true;
    lastSelectedIdRef.current = driverId;
    
    const driver = drivers.find(d => d.id === driverId);
    if (driver && driver.remainingFuel) {
      const currentFuel = {
        Petrol: Number(driver.remainingFuel.Petrol) || 0,
        Diesel: Number(driver.remainingFuel.Diesel) || 0,
        Kerosene: Number(driver.remainingFuel.Kerosene) || 0,
        'V-Power': Number(driver.remainingFuel['V-Power']) || 0
      };
      setFuelData(currentFuel);
      setPreviousFuelData(currentFuel);
      setSelectedDriverName(driver.name || '');
    }
    
    setSelectedDriverId(driverId);
    
    setTimeout(() => {
      isSelectingRef.current = false;
    }, 100);
  }, [drivers]);

  const handleFuelChange = (type, value) => {
    setFuelData(prev => ({
      ...prev,
      [type]: parseFloat(value) || 0
    }));
  };

  const getFuelSummary = (fuelMap) => {
    const available = [];
    Object.keys(fuelMap).forEach(key => {
      const value = Number(fuelMap[key]) || 0;
      if (value > 0) {
        available.push(`${key}: ${Math.round(value)}L`);
      }
    });
    return available.length > 0 ? available.join(' • ') : 'No fuel available';
  };

  const getFuelSummaryFlutter = (fuelMap) => {
    const available = [];
    Object.keys(fuelMap).forEach(key => {
      const value = Number(fuelMap[key]) || 0;
      if (value > 10) {
        available.push(`${key}: ${Math.round(value)}L`);
      }
    });
    return available.length > 0 ? available.join(' • ') : 'No fuel available';
  };

  const hasFuelToGoOnline = (fuelMap) => {
    const values = Object.values(fuelMap);
    for (let i = 0; i < values.length; i++) {
      if (Number(values[i]) > 10) {
        return true;
      }
    }
    return false;
  };

  const formatPhoneNumber = (phone) => {
    let cleaned = phone.replace(/[^0-9]/g, '');
    if (cleaned.startsWith('0') && cleaned.length >= 10) {
      return cleaned;
    }
    if (cleaned.startsWith('254') && cleaned.length >= 12) {
      return '0' + cleaned.substring(3);
    }
    if (cleaned.length >= 9) {
      return '0' + cleaned;
    }
    return phone;
  };

  const checkFuelHistoryByDate = async (date) => {
    if (!date) {
      toast.error('Please select a date');
      return;
    }

    setIsFiltering(true);
    try {
      const startDate = new Date(date);
      startDate.setHours(0, 0, 0, 0);
      const endDate = new Date(date);
      endDate.setHours(23, 59, 59, 999);
      
      const fuelHistoryRef = collection(db, 'fuelHistory');
      const q = query(
        fuelHistoryRef,
        where('timestamp', '>=', startDate.toISOString()),
        where('timestamp', '<=', endDate.toISOString()),
        orderBy('timestamp', 'desc')
      );
      
      const querySnapshot = await getDocs(q);
      const historyData = [];
      querySnapshot.forEach((doc) => {
        historyData.push({ id: doc.id, ...doc.data() });
      });

      const driversSnapshot = await getDocs(collection(db, 'drivers'));
      const allDriversHistory = [];
      driversSnapshot.forEach((driverDoc) => {
        const driverData = driverDoc.data();
        if (driverData.fuelHistory && Array.isArray(driverData.fuelHistory)) {
          const matchedHistory = driverData.fuelHistory.filter(entry => {
            const entryDate = new Date(entry.timestamp);
            return entryDate >= startDate && entryDate <= endDate;
          });
          if (matchedHistory.length > 0) {
            allDriversHistory.push({
              driverId: driverDoc.id,
              driverName: driverData.name || 'Unknown',
              history: matchedHistory
            });
          }
        }
      });

      const combinedResults = {
        fuelHistory: historyData,
        driverHistory: allDriversHistory,
        date: date,
        totalUpdates: historyData.length + allDriversHistory.reduce((sum, d) => sum + d.history.length, 0)
      };

      setDateFilteredHistory(combinedResults);
      setDateFilter(date);
      setShowDateFilterModal(true);

      if (combinedResults.totalUpdates === 0) {
        toast.custom((t) => (
          <div className={`${t.visible ? 'animate-enter' : 'animate-leave'} max-w-md w-full bg-white shadow-lg rounded-lg pointer-events-auto ring-1 ring-black ring-opacity-5`}>
            <div className="p-4">
              <div className="flex items-center">
                <div className="flex-shrink-0">
                  <div className="h-10 w-10 rounded-full bg-yellow-100 flex items-center justify-center text-2xl">
                    ℹ️
                  </div>
                </div>
                <div className="ml-3">
                  <p className="text-sm font-medium text-gray-900">No fuel top-ups found</p>
                  <p className="text-xs text-gray-500">for {new Date(date).toLocaleDateString()}</p>
                  <p className="text-xs text-gray-400 mt-1">No drivers were given fuel on this date</p>
                </div>
              </div>
            </div>
            <div className="flex border-t border-gray-200">
              <button
                onClick={() => toast.dismiss(t.id)}
                className="w-full border border-transparent rounded-none rounded-b-lg p-3 flex items-center justify-center text-sm font-medium text-blue-600 hover:text-blue-500"
              >
                Close
              </button>
            </div>
          </div>
        ));
      } else {
        toast.success(`📋 Found ${combinedResults.totalUpdates} fuel update(s) on ${new Date(date).toLocaleDateString()}`);
      }
    } catch (error) {
      console.error('Error checking fuel history:', error);
      toast.error('Failed to check fuel history: ' + error.message);
    } finally {
      setIsFiltering(false);
    }
  };

  const handleForceRefresh = async () => {
    if (!selectedDriverId) {
      toast.error('Please select a driver first');
      return;
    }
    
    const driver = drivers.find(d => d.id === selectedDriverId);
    if (!driver) {
      toast.error('Driver not found');
      return;
    }
    
    try {
      setLoading(true);
      const now = new Date().toISOString();
      const refreshToken = Math.random().toString(36).substring(2, 15);
      
      const cleanFuelData = {
        Petrol: Number(fuelData.Petrol) || 0,
        Diesel: Number(fuelData.Diesel) || 0,
        Kerosene: Number(fuelData.Kerosene) || 0,
        'V-Power': Number(fuelData['V-Power']) || 0
      };
      
      const hasFuel = hasFuelToGoOnline(cleanFuelData);
      const fuelSummary = getFuelSummaryFlutter(cleanFuelData);
      
      await updateDoc(doc(db, 'drivers', selectedDriverId), {
        _refreshToken: refreshToken,
        _forceRefresh: now,
        _lastSync: now,
        lastUpdate: now,
        fuelUpdatedAt: now,
        remainingFuel: cleanFuelData,
        isAvailable: hasFuel,
        isOnline: hasFuel ? (driver.isOnline || false) : false,
        status: hasFuel ? 'available' : 'offline',
        lastFuelUpdate: {
          timestamp: now,
          updatedBy: 'Admin (Force)',
          fuelData: cleanFuelData,
          fuelSummary: fuelSummary,
          hasFuel: hasFuel
        }
      });
      
      toast.success('🔄 Force refresh sent to driver app!');
    } catch (error) {
      console.error('Error refreshing:', error);
      toast.error('Error refreshing: ' + error.message);
    } finally {
      setLoading(false);
    }
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    
    if (!selectedDriverId) {
      toast.error('Please select a driver');
      return;
    }

    const driver = drivers.find(d => d.id === selectedDriverId);
    if (!driver) {
      toast.error('Driver not found');
      return;
    }

    setLoading(true);
    try {
      const cleanFuelData = {
        Petrol: Number(fuelData.Petrol) || 0,
        Diesel: Number(fuelData.Diesel) || 0,
        Kerosene: Number(fuelData.Kerosene) || 0,
        'V-Power': Number(fuelData['V-Power']) || 0
      };
      
      const fuelUpdates = [];
      let totalFuelAdded = 0;
      let totalFuelRemoved = 0;
      
      Object.keys(cleanFuelData).forEach(fuelType => {
        const previousAmount = Number(previousFuelData[fuelType]) || 0;
        const newAmount = Number(cleanFuelData[fuelType]) || 0;
        const addedAmount = newAmount - previousAmount;
        
        if (addedAmount !== 0) {
          fuelUpdates.push({
            fuelType,
            previousAmount,
            newAmount,
            addedAmount,
            action: addedAmount > 0 ? 'added' : 'removed'
          });
          if (addedAmount > 0) {
            totalFuelAdded += addedAmount;
          } else {
            totalFuelRemoved += Math.abs(addedAmount);
          }
        }
      });

      const fuelSummary = getFuelSummaryFlutter(cleanFuelData);
      const totalFuel = Object.values(cleanFuelData).reduce((sum, val) => sum + Number(val), 0);
      const hasFuel = hasFuelToGoOnline(cleanFuelData);
      
      const now = new Date().toISOString();
      const refreshToken = Math.random().toString(36).substring(2, 15);
      
      const historyEntry = {
        type: 'fuel_update',
        timestamp: now,
        date: now,
        dateOnly: new Date().toISOString().split('T')[0],
        driverName: driver.name || 'Unknown Driver',
        vehiclePlate: driver.numberPlate || '',
        fuelAvailable: fuelSummary,
        fuelUpdates: fuelUpdates,
        remainingFuelAfter: cleanFuelData,
        totalFuel: totalFuel,
        totalAdded: totalFuelAdded,
        totalRemoved: totalFuelRemoved,
        updatedBy: 'Admin'
      };

      await updateDoc(doc(db, 'drivers', selectedDriverId), {
        remainingFuel: cleanFuelData,
        fuelUpdatedAt: now,
        lastUpdate: now,
        fuelHistory: arrayUnion(historyEntry),
        onlineHistory: arrayUnion({
          type: 'fuel_update',
          timestamp: now,
          date: now,
          dateOnly: new Date().toISOString().split('T')[0],
          fuelAvailable: fuelSummary,
          driverName: driver.name || '',
          vehiclePlate: driver.numberPlate || '',
          location: {
            lat: driver.lat || 0,
            lng: driver.lng || 0
          }
        }),
        isAvailable: hasFuel,
        isOnline: hasFuel ? (driver.isOnline || false) : false,
        status: hasFuel ? 'available' : 'offline',
        _refreshToken: refreshToken,
        _lastSync: now,
        _lastFuelUpdate: now,
        lastFuelUpdate: {
          timestamp: now,
          updatedBy: 'Admin',
          fuelData: cleanFuelData,
          fuelSummary: fuelSummary,
          hasFuel: hasFuel
        }
      });

      await addDoc(collection(db, 'drivers', selectedDriverId, 'fuelHistory'), {
        ...historyEntry,
        driverId: selectedDriverId,
        createdAt: serverTimestamp()
      });

      await addDoc(collection(db, 'fuelHistory'), {
        ...historyEntry,
        driverId: selectedDriverId,
        driverEmail: driver.email || '',
        serverTimestamp: serverTimestamp(),
        createdAt: serverTimestamp()
      });

      setPreviousFuelData(cleanFuelData);

      toast.success(
        <div>
          <div><strong>✅ Fuel updated for {driver.name || 'driver'}!</strong></div>
          <div className="text-xs mt-1">{fuelSummary}</div>
          <div className="text-xs mt-1 text-green-600">
            Status: {hasFuel ? '🟢 Available to go online' : '🔴 Not enough fuel (need > 10L)'}
          </div>
          <div className="text-xs mt-1 text-blue-500">🔄 Driver app will update automatically</div>
        </div>,
        { duration: 6000 }
      );
      
    } catch (error) {
      console.error('Error updating fuel:', error);
      toast.error('Failed to update fuel: ' + error.message);
    } finally {
      setLoading(false);
    }
  };

  const handleCreateDriver = async (e) => {
    e.preventDefault();
    setCreateLoading(true);

    try {
      if (!newDriver.name || !newDriver.email || !newDriver.phone) {
        toast.error('Please fill in all required fields');
        setCreateLoading(false);
        return;
      }

      const formattedPhone = formatPhoneNumber(newDriver.phone);
      const docId = `admin_${Date.now()}_${Math.random().toString(36).substring(2, 6)}`;

      const remainingFuel = {
        'Petrol': Number(newDriver.petrol) || 0,
        'Diesel': Number(newDriver.diesel) || 0,
        'Kerosene': Number(newDriver.kerosene) || 0,
        'V-Power': Number(newDriver.vpower) || 0
      };

      const hasFuel = hasFuelToGoOnline(remainingFuel);
      const now = new Date().toISOString();
      const fuelSummary = getFuelSummaryFlutter(remainingFuel);

      const driverData = {
        'userId': docId,
        'name': newDriver.name,
        'phone': formattedPhone,
        'email': newDriver.email,
        'userType': 'driver',
        'vehicleType': newDriver.vehicleType || 'Pending Assignment',
        'numberPlate': newDriver.numberPlate || 'Pending Assignment',
        'pricePerKm': 0,
        'isApproved': true,
        'isOnline': false,
        'isAvailable': hasFuel,
        'status': hasFuel ? 'available' : 'offline',
        'orderAccepted': false,
        'lat': 0.0,
        'lng': 0.0,
        'heading': 0.0,
        'speed': 0.0,
        'activeOrderId': null,
        'orderStartedAt': null,
        'currentClientName': null,
        'currentClientPhone': null,
        'currentClientLocation': null,
        'currentClientPhoto': null,
        'remainingFuel': remainingFuel,
        'fuelUpdatedAt': serverTimestamp(),
        'fuelHistory': [],
        'salesHistory': [],
        'totalFuelSoldToday': 0.0,
        'totalRevenueToday': 0.0,
        'lastSaleDate': null,
        'lastSaleFuelType': null,
        'lastSaleLitres': 0.0,
        'lastSaleAmount': 0.0,
        'lastSaleTime': null,
        'lastOrderTime': null,
        'totalOrders': 0,
        'completedOrders': 0,
        'lastCompletedOrderAt': null,
        'onlineHistory': [],
        'lastOnlineTime': null,
        'lastOfflineTime': null,
        'lastUpdate': serverTimestamp(),
        'profileComplete': true,
        'driverPhoto': '',
        'rating': 0.0,
        'driverSince': serverTimestamp(),
        'createdAt': serverTimestamp(),
        '_createdBy': 'admin',
        '_createdAt': now,
        '_adminCreated': true
      };

      if (hasFuel) {
        const fuelUpdates = Object.keys(remainingFuel).map(key => ({
          fuelType: key,
          previousAmount: 0,
          newAmount: remainingFuel[key],
          addedAmount: remainingFuel[key],
          action: remainingFuel[key] > 0 ? 'added' : 'none'
        }));

        const fuelHistoryEntry = {
          type: 'fuel_update',
          timestamp: now,
          date: now,
          dateOnly: new Date().toISOString().split('T')[0],
          driverName: newDriver.name,
          vehiclePlate: newDriver.numberPlate || 'Pending Assignment',
          fuelAvailable: fuelSummary,
          fuelUpdates: fuelUpdates,
          remainingFuelAfter: remainingFuel,
          totalFuel: Object.values(remainingFuel).reduce((a, b) => a + Number(b), 0),
          totalAdded: Object.values(remainingFuel).reduce((a, b) => a + Number(b), 0),
          totalRemoved: 0,
          updatedBy: 'Admin'
        };

        driverData.fuelHistory = [fuelHistoryEntry];
        driverData.onlineHistory = [{
          type: 'online',
          timestamp: now,
          date: now,
          dateOnly: new Date().toISOString().split('T')[0],
          fuelAvailable: fuelSummary,
          driverName: newDriver.name,
          vehiclePlate: newDriver.numberPlate || 'Pending Assignment',
          location: { lat: 0, lng: 0 }
        }];

        await addDoc(collection(db, 'drivers', docId, 'fuelHistory'), {
          ...fuelHistoryEntry,
          driverId: docId,
          createdAt: serverTimestamp()
        });

        await addDoc(collection(db, 'fuelHistory'), {
          ...fuelHistoryEntry,
          driverId: docId,
          driverEmail: newDriver.email,
          serverTimestamp: serverTimestamp(),
          createdAt: serverTimestamp()
        });
      }

      await setDoc(doc(db, 'drivers', docId), driverData);

      toast.success(
        <div>
          <div><strong>✅ Driver created successfully!</strong></div>
          <div className="text-xs mt-1">Name: {newDriver.name}</div>
          <div className="text-xs">Email: {newDriver.email}</div>
          <div className="text-xs mt-1 text-green-600">Fuel: {fuelSummary}</div>
        </div>,
        { duration: 6000 }
      );

      setNewDriver({
        name: '',
        email: '',
        phone: '',
        petrol: 0,
        diesel: 0,
        kerosene: 0,
        vpower: 0,
        vehicleType: 'Pending Assignment',
        numberPlate: 'Pending Assignment'
      });
      setShowCreateDriver(false);

    } catch (error) {
      console.error('Error creating driver:', error);
      toast.error('Failed to create driver: ' + error.message);
    } finally {
      setCreateLoading(false);
    }
  };

  const viewDriverHistory = async (driverId) => {
    try {
      const driver = drivers.find(d => d.id === driverId);
      if (driver && driver.fuelHistory && Array.isArray(driver.fuelHistory) && driver.fuelHistory.length > 0) {
        setFuelHistory(driver.fuelHistory);
        setShowHistory(true);
        return;
      }
      
      const historyRef = collection(db, 'drivers', driverId, 'fuelHistory');
      const q = query(historyRef, orderBy('timestamp', 'desc'));
      const querySnapshot = await getDocs(q);
      const historyData = [];
      querySnapshot.forEach((doc) => {
        historyData.push({ id: doc.id, ...doc.data() });
      });
      
      if (historyData.length === 0) {
        toast.info('No fuel history found for this driver');
        return;
      }
      
      setFuelHistory(historyData);
      setShowHistory(true);
    } catch (error) {
      console.error('Error fetching driver history:', error);
      toast.error('Failed to fetch driver history');
    }
  };

  return (
    <div className={`p-4 md:p-6 transition-colors duration-300 ${getBackgroundClass()}`}>
      <div className="max-w-7xl mx-auto space-y-6">
        <div className="flex items-center justify-between">
          <div>
            <h1 className={`text-2xl font-bold ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'}`}>⛽ Update Driver Fuel</h1>
            <p className={`text-sm ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>Update fuel levels for individual drivers</p>
            {selectedDriverName && (
              <p className={`text-sm text-blue-600 mt-1`}>Selected: <strong>{selectedDriverName}</strong></p>
            )}
          </div>
          <div className="flex space-x-3">
            <Link href="/fuel" className={`text-sm ${userBackground === 'dark' ? 'text-gray-400 hover:text-gray-200' : 'text-gray-500 hover:text-gray-700'} flex items-center space-x-1`}>
              <span>←</span>
              <span>Back to Fuel</span>
            </Link>
            <button
              onClick={() => setShowCreateDriver(true)}
              className="px-4 py-2 text-sm font-medium text-white bg-green-500 rounded-lg hover:bg-green-600 transition"
            >
              + Add Driver
            </button>
          </div>
        </div>

        <div className={`rounded-xl shadow-sm p-6 border ${userBackground === 'dark' ? 'border-gray-700' : 'border-gray-100'} ${getCardClass()}`}>
          <form onSubmit={handleSubmit} className="space-y-6 max-w-2xl">
            <div>
              <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-2`}>Select Driver</label>
              <select
                value={selectedDriverId}
                onChange={(e) => handleDriverSelect(e.target.value)}
                className={`w-full px-4 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500 ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'}`}
              >
                <option value="">Select a driver...</option>
                {drivers.map(driver => {
                  const hasFuel = driver.remainingFuel && Object.values(driver.remainingFuel).some(v => Number(v) > 10);
                  const fuelCount = driver.remainingFuel ? Object.values(driver.remainingFuel).reduce((a, b) => a + Number(b), 0) : 0;
                  return (
                    <option key={driver.id} value={driver.id}>
                      {driver.name} - {driver.email}
                      {driver._adminCreated ? ' (Admin)' : ' (App)'}
                      {hasFuel ? ` 🟢 ${Math.round(fuelCount)}L` : ' 🔴 No Fuel'}
                    </option>
                  );
                })}
              </select>
            </div>

            {selectedDriverId && (
              <>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                  {Object.keys(fuelData).map((fuelType) => {
                    const previous = Number(previousFuelData[fuelType]) || 0;
                    const current = Number(fuelData[fuelType]) || 0;
                    const difference = current - previous;
                    
                    return (
                      <div key={fuelType}>
                        <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-2`}>
                          {fuelType} (Litres)
                        </label>
                        <input
                          type="number"
                          value={fuelData[fuelType]}
                          onChange={(e) => handleFuelChange(fuelType, e.target.value)}
                          className={`w-full px-4 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500 ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'}`}
                          step="1"
                          min="0"
                        />
                        {difference !== 0 && (
                          <p className={`text-xs mt-1 ${difference > 0 ? 'text-green-600' : 'text-red-600'}`}>
                            {difference > 0 ? '+' : ''}{difference.toFixed(0)}L from previous
                          </p>
                        )}
                      </div>
                    );
                  })}
                </div>

                {(() => {
                  const hasFuel = hasFuelToGoOnline(fuelData);
                  const totalFuel = Object.values(fuelData).reduce((sum, val) => sum + Number(val), 0);
                  return (
                    <div className={`rounded-lg p-3 border ${hasFuel ? 'bg-green-50 border-green-200' : 'bg-red-50 border-red-200'}`}>
                      <p className={`text-sm ${hasFuel ? 'text-green-700' : 'text-red-700'}`}>
                        <span className="font-semibold">Fuel Summary:</span> {getFuelSummaryFlutter(fuelData)}
                      </p>
                      <p className="text-xs mt-1 text-gray-600">
                        Total: {totalFuel.toFixed(0)}L
                        {hasFuel ? ' ✅ Available for online' : ' ❌ Need at least 10L of any fuel to go online'}
                      </p>
                      <p className="text-xs mt-1 text-gray-400">
                        * Flutter requires any fuel type &gt; 10L to go online
                      </p>
                    </div>
                  );
                })()}

                <div className="flex justify-between items-center pt-6 border-t border-gray-200">
                  <div className="flex space-x-2">
                    <button
                      type="button"
                      onClick={() => viewDriverHistory(selectedDriverId)}
                      className={`px-4 py-2 text-sm font-medium ${userBackground === 'dark' ? 'text-blue-400 bg-blue-900/30 hover:bg-blue-900/50' : 'text-blue-600 bg-blue-50 hover:bg-blue-100'} rounded-lg transition`}
                    >
                      📜 View History
                    </button>
                    <button
                      type="button"
                      onClick={handleForceRefresh}
                      disabled={loading}
                      className={`px-4 py-2 text-sm font-medium ${userBackground === 'dark' ? 'text-orange-400 bg-orange-900/30 hover:bg-orange-900/50' : 'text-orange-600 bg-orange-50 hover:bg-orange-100'} rounded-lg transition disabled:opacity-50`}
                    >
                      🔄 Force Refresh
                    </button>
                  </div>
                  <div className="flex space-x-3">
                    <button
                      type="button"
                      onClick={() => {
                        setSelectedDriverId('');
                        setFuelData({ Petrol: 0, Diesel: 0, Kerosene: 0, 'V-Power': 0 });
                        setPreviousFuelData({ Petrol: 0, Diesel: 0, Kerosene: 0, 'V-Power': 0 });
                        setSelectedDriverName('');
                        lastSelectedIdRef.current = '';
                      }}
                      className={`px-4 py-2 text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300 bg-gray-700 hover:bg-gray-600' : 'text-gray-700 bg-gray-100 hover:bg-gray-200'} rounded-lg transition`}
                    >
                      Cancel
                    </button>
                    <button
                      type="submit"
                      disabled={loading}
                      className="px-4 py-2 text-sm font-medium text-white bg-green-500 rounded-lg hover:bg-green-600 transition disabled:opacity-50"
                    >
                      {loading ? 'Updating...' : 'Update Fuel'}
                    </button>
                  </div>
                </div>
              </>
            )}
          </form>
        </div>

        {/* Driver History Modal */}
        {showHistory && (
          <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
            <div className={`rounded-xl p-6 max-w-2xl w-full max-h-[80vh] overflow-y-auto ${getCardClass()}`}>
              <div className="flex justify-between items-center mb-4">
                <h3 className={`text-lg font-semibold ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'}`}>Driver Fuel History</h3>
                <button
                  onClick={() => setShowHistory(false)}
                  className={`${userBackground === 'dark' ? 'text-gray-400 hover:text-gray-200' : 'text-gray-500 hover:text-gray-700'}`}
                >
                  ✕
                </button>
              </div>
              {!fuelHistory || fuelHistory.length === 0 ? (
                <div className={`text-center py-8 ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>
                  <p>No fuel history found for this driver</p>
                </div>
              ) : (
                <div className="space-y-4">
                  {fuelHistory.slice().reverse().map((entry, idx) => (
                    <div key={idx} className={`border rounded-lg p-4 ${userBackground === 'dark' ? 'border-gray-700' : 'border-gray-200'}`}>
                      <div className="flex justify-between items-start">
                        <div>
                          <p className={`text-sm font-medium ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'}`}>
                            {entry.date ? new Date(entry.date).toLocaleString() : new Date(entry.timestamp).toLocaleString()}
                          </p>
                          <p className={`text-xs ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>Updated by: {entry.updatedBy || 'Admin'}</p>
                        </div>
                        <div className="text-right">
                          {entry.totalAdded > 0 && (
                            <span className="text-xs text-green-600">+{entry.totalAdded.toFixed(0)}L added</span>
                          )}
                          {entry.totalRemoved > 0 && (
                            <span className="text-xs text-red-600">-{entry.totalRemoved.toFixed(0)}L removed</span>
                          )}
                        </div>
                      </div>
                      <div className="mt-2 flex flex-wrap gap-2">
                        {entry.fuelUpdates && entry.fuelUpdates.map((update, uidx) => (
                          <span key={uidx} className={`text-xs px-2 py-1 rounded ${userBackground === 'dark' ? 'bg-gray-700' : 'bg-gray-100'}`}>
                            {update.fuelType}: 
                            <span className={update.addedAmount > 0 ? 'text-green-600' : 'text-red-600'}>
                              {update.addedAmount > 0 ? '+' : ''}{update.addedAmount.toFixed(0)}L
                            </span>
                          </span>
                        ))}
                        {entry.fuelAvailable && (
                          <span className="text-xs bg-blue-50 px-2 py-1 rounded text-blue-700">
                            {entry.fuelAvailable}
                          </span>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        )}

        {/* Date Filter History Modal - UPDATED: Only shows fuel added to drivers */}
        {showDateFilterModal && (
          <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
            <div className={`rounded-xl p-6 max-w-3xl w-full max-h-[80vh] overflow-y-auto ${getCardClass()}`}>
              <div className="flex justify-between items-center mb-4">
                <div>
                  <h3 className={`text-lg font-semibold ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'}`}>
                    📊 Fuel Top-ups for {new Date(dateFilter).toLocaleDateString()}
                  </h3>
                  <p className={`text-sm ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>
                    {dateFilteredHistory.driverHistory?.reduce((sum, d) => sum + d.history.length, 0) || 0} top-up(s) found
                  </p>
                </div>
                <button
                  onClick={() => setShowDateFilterModal(false)}
                  className={`${userBackground === 'dark' ? 'text-gray-400 hover:text-gray-200' : 'text-gray-500 hover:text-gray-700'}`}
                >
                  ✕
                </button>
              </div>

              {!dateFilteredHistory.driverHistory || dateFilteredHistory.driverHistory.length === 0 ? (
                <div className="text-center py-12">
                  <div className="text-6xl mb-4">🔍</div>
                  <h4 className={`text-lg font-medium ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'}`}>No fuel top-ups found</h4>
                  <p className={`text-sm ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'} mt-1`}>No drivers received fuel on {new Date(dateFilter).toLocaleDateString()}</p>
                </div>
              ) : (
                <div className="space-y-4">
                  {dateFilteredHistory.driverHistory.map((driverEntry, idx) => (
                    <div key={`driver-${idx}`} className={`border rounded-lg p-4 ${userBackground === 'dark' ? 'border-blue-700 bg-blue-900/20' : 'border-blue-200 bg-blue-50'}`}>
                      <div className="flex items-center justify-between mb-3">
                        <div>
                          <p className={`text-sm font-semibold ${userBackground === 'dark' ? 'text-blue-300' : 'text-blue-800'}`}>
                            🚛 {driverEntry.driverName}
                          </p>
                          <p className={`text-xs ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>
                            {driverEntry.history.length} top-up(s) on this day
                          </p>
                        </div>
                        <div className="text-right">
                          <span className={`text-xs font-medium ${userBackground === 'dark' ? 'text-green-400' : 'text-green-600'}`}>
                            +{driverEntry.history.reduce((sum, entry) => sum + (entry.totalAdded || 0), 0).toFixed(0)}L total
                          </span>
                        </div>
                      </div>
                      
                      {driverEntry.history.map((entry, hidx) => {
                        const isAdd = entry.totalAdded > 0 || entry.action === 'add' || entry.action === 'top-up';
                        const amount = entry.totalAdded || entry.amount || 0;
                        const fuelType = entry.fuelType || 'Multiple';
                        const date = entry.date || entry.timestamp;
                        
                        return (
                          <div key={`entry-${hidx}`} className={`mt-2 p-3 rounded border ${userBackground === 'dark' ? 'bg-gray-800 border-gray-700' : 'bg-white border-gray-200'}`}>
                            <div className="flex justify-between items-start">
                              <div>
                                <p className={`text-xs ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>
                                  {date ? new Date(date).toLocaleTimeString() : 'N/A'}
                                </p>
                                <p className={`text-xs ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>
                                  Updated by: {entry.updatedBy || 'Admin'}
                                </p>
                              </div>
                              <div className="text-right">
                                {isAdd ? (
                                  <span className="text-sm font-bold text-green-600">
                                    +{amount.toFixed(0)}L {fuelType}
                                  </span>
                                ) : (
                                  <span className="text-sm font-bold text-red-600">
                                    -{amount.toFixed(0)}L {fuelType}
                                  </span>
                                )}
                              </div>
                            </div>
                            
                            <div className="mt-2 flex flex-wrap gap-2">
                              {entry.fuelUpdates && entry.fuelUpdates.length > 0 ? (
                                entry.fuelUpdates.map((update, uidx) => {
                                  const isAddUpdate = update.addedAmount > 0 || update.action === 'add' || update.action === 'top-up';
                                  const updateAmount = Math.abs(update.addedAmount || update.amount || 0);
                                  if (updateAmount === 0) return null;
                                  return (
                                    <span key={uidx} className={`text-xs px-2 py-1 rounded ${userBackground === 'dark' ? 'bg-gray-700' : 'bg-gray-100'}`}>
                                      {update.fuelType}: 
                                      <span className={isAddUpdate ? 'text-green-600 font-bold' : 'text-red-600 font-bold'}>
                                        {isAddUpdate ? '+' : '-'}{updateAmount.toFixed(0)}L
                                        {update.previousAmount !== undefined && (
                                          <span className="text-gray-400 font-normal">
                                            {' '}({update.previousAmount.toFixed(0)} → {update.newAmount.toFixed(0)}L)
                                          </span>
                                        )}
                                      </span>
                                    </span>
                                  );
                                })
                              ) : entry.fuelType && entry.amount ? (
                                <span className={`text-xs px-2 py-1 rounded ${userBackground === 'dark' ? 'bg-gray-700' : 'bg-gray-100'}`}>
                                  {entry.fuelType}: 
                                  <span className={isAdd ? 'text-green-600 font-bold' : 'text-red-600 font-bold'}>
                                    {isAdd ? '+' : '-'}{entry.amount.toFixed(0)}L
                                  </span>
                                </span>
                              ) : null}
                              
                              {entry.fuelAvailable && (
                                <span className="text-xs bg-blue-50 px-2 py-1 rounded text-blue-700">
                                  📊 {entry.fuelAvailable}
                                </span>
                              )}
                            </div>
                            
                            {entry.remainingFuelAfter && (
                              <div className="mt-2 pt-2 border-t ${userBackground === 'dark' ? 'border-gray-700' : 'border-gray-100'}">
                                <p className={`text-xs ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>
                                  Remaining: {Object.entries(entry.remainingFuelAfter).map(([key, val]) => 
                                    `${key}: ${Number(val).toFixed(0)}L`
                                  ).join(' • ')}
                                </p>
                              </div>
                            )}
                          </div>
                        );
                      })}
                    </div>
                  ))}
                </div>
              )}
              
              <div className="mt-4 pt-4 border-t ${userBackground === 'dark' ? 'border-gray-700' : 'border-gray-200'}">
                <p className={`text-xs ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-400'}`}>
                  💡 Showing all drivers who received fuel top-ups on {new Date(dateFilter).toLocaleDateString()}
                </p>
              </div>
            </div>
          </div>
        )}

        {/* Create Driver Modal */}
        {showCreateDriver && (
          <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
            <div className={`rounded-xl p-6 max-w-2xl w-full max-h-[90vh] overflow-y-auto ${getCardClass()}`}>
              <div className="flex justify-between items-center mb-4">
                <h3 className={`text-lg font-semibold ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'}`}>Add New Driver</h3>
                <button
                  onClick={() => setShowCreateDriver(false)}
                  className={`${userBackground === 'dark' ? 'text-gray-400 hover:text-gray-200' : 'text-gray-500 hover:text-gray-700'}`}
                >
                  ✕
                </button>
              </div>

              <form onSubmit={handleCreateDriver}>
                <div className="space-y-4">
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <div>
                      <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-1`}>Full Name *</label>
                      <input
                        type="text"
                        value={newDriver.name}
                        onChange={(e) => setNewDriver({...newDriver, name: e.target.value})}
                        className={`w-full px-3 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500 ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'}`}
                        required
                      />
                    </div>
                    <div>
                      <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-1`}>Email *</label>
                      <input
                        type="email"
                        value={newDriver.email}
                        onChange={(e) => setNewDriver({...newDriver, email: e.target.value})}
                        className={`w-full px-3 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500 ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'}`}
                        required
                      />
                    </div>
                    <div>
                      <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-1`}>Phone *</label>
                      <input
                        type="text"
                        value={newDriver.phone}
                        onChange={(e) => setNewDriver({...newDriver, phone: e.target.value})}
                        className={`w-full px-3 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500 ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'}`}
                        placeholder="0712345678"
                        required
                      />
                    </div>
                    <div>
                      <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-1`}>Vehicle Type</label>
                      <select
                        value={newDriver.vehicleType}
                        onChange={(e) => setNewDriver({...newDriver, vehicleType: e.target.value})}
                        className={`w-full px-3 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500 ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'}`}
                      >
                        <option value="Pending Assignment">Pending Assignment</option>
                        <option value="Fuel Truck">Fuel Truck</option>
                        <option value="Small Truck">Small Truck</option>
                        <option value="Medium Truck">Medium Truck</option>
                        <option value="Large Truck">Large Truck</option>
                        <option value="Van">Van</option>
                      </select>
                    </div>
                    <div>
                      <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-1`}>Number Plate</label>
                      <input
                        type="text"
                        value={newDriver.numberPlate}
                        onChange={(e) => setNewDriver({...newDriver, numberPlate: e.target.value.toUpperCase()})}
                        className={`w-full px-3 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500 ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'}`}
                        placeholder="KDN 123E"
                      />
                    </div>
                  </div>

                  <div className="border-t pt-4">
                    <h4 className={`text-md font-medium ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'} mb-3`}>⛽ Initial Fuel</h4>
                    <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                      <div>
                        <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-1`}>Petrol (L)</label>
                        <input
                          type="number"
                          value={newDriver.petrol}
                          onChange={(e) => setNewDriver({...newDriver, petrol: parseFloat(e.target.value) || 0})}
                          className={`w-full px-3 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500 ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'}`}
                          step="1"
                          min="0"
                        />
                      </div>
                      <div>
                        <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-1`}>Diesel (L)</label>
                        <input
                          type="number"
                          value={newDriver.diesel}
                          onChange={(e) => setNewDriver({...newDriver, diesel: parseFloat(e.target.value) || 0})}
                          className={`w-full px-3 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500 ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'}`}
                          step="1"
                          min="0"
                        />
                      </div>
                      <div>
                        <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-1`}>Kerosene (L)</label>
                        <input
                          type="number"
                          value={newDriver.kerosene}
                          onChange={(e) => setNewDriver({...newDriver, kerosene: parseFloat(e.target.value) || 0})}
                          className={`w-full px-3 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500 ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'}`}
                          step="1"
                          min="0"
                        />
                      </div>
                      <div>
                        <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-1`}>V-Power (L)</label>
                        <input
                          type="number"
                          value={newDriver.vpower}
                          onChange={(e) => setNewDriver({...newDriver, vpower: parseFloat(e.target.value) || 0})}
                          className={`w-full px-3 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500 ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'}`}
                          step="1"
                          min="0"
                        />
                      </div>
                    </div>
                    <p className={`text-xs ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-400'} mt-2`}>
                      * Driver needs at least 10L of any fuel to go online (matches Flutter)
                    </p>
                  </div>

                  <div className="flex justify-end space-x-3 pt-6 border-t">
                    <button
                      type="button"
                      onClick={() => setShowCreateDriver(false)}
                      className={`px-4 py-2 text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300 bg-gray-700 hover:bg-gray-600' : 'text-gray-700 bg-gray-100 hover:bg-gray-200'} rounded-lg transition`}
                    >
                      Cancel
                    </button>
                    <button
                      type="submit"
                      disabled={createLoading}
                      className="px-4 py-2 text-sm font-medium text-white bg-green-500 rounded-lg hover:bg-green-600 transition disabled:opacity-50"
                    >
                      {createLoading ? 'Creating...' : 'Create Driver'}
                    </button>
                  </div>
                </div>
              </form>
            </div>
          </div>
        )}

        {/* Date Filter Section */}
        <div className={`rounded-xl shadow-sm p-6 border ${userBackground === 'dark' ? 'border-gray-700' : 'border-gray-100'} ${getCardClass()}`}>
          <h2 className={`text-lg font-semibold ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'} mb-4`}>📅 Check Fuel Top-ups by Date</h2>
          <div className="flex flex-wrap items-center gap-4">
            <div>
              <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-1`}>Select Date</label>
              <input
                type="date"
                id="historyDate"
                className={`px-4 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500 ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'}`}
                onChange={(e) => setDateFilter(e.target.value)}
              />
            </div>
            <button
              onClick={() => {
                const dateInput = document.getElementById('historyDate') as HTMLInputElement;
                if (!dateInput.value) {
                  toast.error('Please select a date');
                  return;
                }
                checkFuelHistoryByDate(dateInput.value);
              }}
              disabled={isFiltering}
              className="px-4 py-2 text-sm font-medium text-white bg-blue-500 rounded-lg hover:bg-blue-600 transition disabled:opacity-50 mt-5"
            >
              {isFiltering ? 'Checking...' : '🔍 Check Top-ups'}
            </button>
            {dateFilter && (
              <span className={`text-sm ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'} mt-5`}>
                Showing top-ups for: <strong>{new Date(dateFilter).toLocaleDateString()}</strong>
              </span>
            )}
          </div>
          <p className={`text-xs ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-400'} mt-2`}>
            * Shows all drivers who received fuel top-ups on the selected date
          </p>
        </div>
      </div>
    </div>
  );
}