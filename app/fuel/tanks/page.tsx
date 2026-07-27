'use client';

import { useState, useEffect, useRef, useCallback, useMemo } from 'react';
import { db, auth } from '../../../lib/firebase';
import { collection, onSnapshot, doc, updateDoc, getDoc, getDocs, setDoc, query, where, runTransaction } from 'firebase/firestore';
import Link from 'next/link';
import toast from 'react-hot-toast';

// ✅ SHARED VALIDATION FUNCTION
export const validateAndUpdateFuelStock = async (fuelType, amount, action, reason = '', updatedBy = 'Admin') => {
  try {
    if (!fuelType || !amount || amount <= 0) {
      throw new Error('Invalid fuel type or amount');
    }

    const TANK_CAPACITY = { Petrol: 100000, Diesel: 100000, Kerosene: 100000, 'V-Power': 100000 };
    const capacity = TANK_CAPACITY[fuelType] || 0;
    const companyRef = doc(db, 'company', 'fuelStock');

    const result = await runTransaction(db, async (transaction) => {
      const snap = await transaction.get(companyRef);
      
      if (!snap.exists()) {
        throw new Error('Fuel stock document does not exist');
      }

      const data = snap.data();
      const currentStock = data.stock || { Petrol: 0, Diesel: 0, Kerosene: 0, 'V-Power': 0 };
      const currentAmount = Math.min(currentStock[fuelType] || 0, capacity);
      const existingLogs = data.activityLog || [];

      let newAmount;
      let actionType;

      if (action === 'add') {
        if (currentAmount >= capacity - 0.001) {
          throw new Error(`${fuelType} tank is FULL! Current: ${currentAmount.toFixed(1)}L, Capacity: ${capacity}L`);
        }
        newAmount = currentAmount + amount;
        if (newAmount > capacity + 0.001) {
          const availableSpace = capacity - currentAmount;
          throw new Error(`Cannot add ${amount}L! ${fuelType} tank capacity is ${capacity}L. Only ${availableSpace.toFixed(1)}L space available.`);
        }
        actionType = 'Top-up';
      } else if (action === 'remove') {
        if (currentAmount < amount) {
          throw new Error(`Cannot remove ${amount}L! Only ${currentAmount.toFixed(1)}L available.`);
        }
        newAmount = currentAmount - amount;
        actionType = 'Removal';
      } else {
        throw new Error('Invalid action. Must be "add" or "remove"');
      }

      const updatedStock = { ...currentStock, [fuelType]: newAmount };
      const logEntry = {
        fuelType,
        amount,
        action,
        actionType,
        reason: reason || `${actionType} of ${amount}L ${fuelType}`,
        timestamp: new Date().toISOString(),
        date: new Date().toLocaleString(),
        previousTankAmount: currentAmount,
        newTankAmount: newAmount,
        updatedBy: updatedBy,
        capacityInfo: `${newAmount}/${capacity}L (${((newAmount/capacity)*100).toFixed(1)}%)`
      };

      const updatedLogs = [logEntry, ...existingLogs].slice(0, 100);
      transaction.update(companyRef, {
        stock: updatedStock,
        activityLog: updatedLogs,
        lastUpdated: new Date().toISOString()
      });

      return { success: true, previousAmount: currentAmount, newAmount: newAmount, capacity: capacity, logEntry: logEntry };
    });

    return result;
  } catch (error) {
    console.error('Validation error:', error);
    throw error;
  }
};

export default function FuelTanks() {
  const [totalStock, setTotalStock] = useState({ Petrol: 0, Diesel: 0, Kerosene: 0, 'V-Power': 0 });
  const [loading, setLoading] = useState(true);
  const [selectedFuel, setSelectedFuel] = useState('Petrol');
  const [animate, setAnimate] = useState(false);
  const [previousStock, setPreviousStock] = useState({});
  const [activityLog, setActivityLog] = useState([]);
  const [fuelDeliveries, setFuelDeliveries] = useState([]);
  const [processedDeliveries, setProcessedDeliveries] = useState(new Set());
  const [showAllActivities, setShowAllActivities] = useState(false);
  const [filteredActivities, setFilteredActivities] = useState([]);
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');
  const [isFiltering, setIsFiltering] = useState(false);
  const [userBackground, setUserBackground] = useState('white');

  // ✅ Refs for performance
  const isProcessingRef = useRef(false);
  const processingQueueRef = useRef(new Set());
  const listenerUnsubscribeRef = useRef<(() => void) | null>(null);
  const toastShownRef = useRef<Set<string>>(new Set());

  const TANK_CAPACITY = { Petrol: 100000, Diesel: 100000, Kerosene: 100000, 'V-Power': 100000 };

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

  // ✅ OPTIMIZED: Load initial data once
  useEffect(() => {
    const loadInitialData = async () => {
      try {
        const docRef = doc(db, 'company', 'fuelStock');
        const docSnap = await getDoc(docRef);
        if (docSnap.exists()) {
          const data = docSnap.data();
          setActivityLog(data.activityLog || []);
          setFuelDeliveries(data.fuelDeliveries || []);
          setFilteredActivities(data.activityLog || []);
          if (data.stock) {
            setTotalStock(data.stock);
            setPreviousStock(data.stock);
          }
        } else {
          const defaultStock = { Petrol: 0, Diesel: 0, Kerosene: 0, 'V-Power': 0 };
          await setDoc(docRef, { stock: defaultStock, activityLog: [], lastUpdated: new Date().toISOString() });
          setTotalStock(defaultStock);
          setPreviousStock(defaultStock);
        }
      } catch (error) {
        console.error('Error loading data:', error);
      } finally {
        setLoading(false);
      }
    };
    loadInitialData();
  }, []);

  // ✅ OPTIMIZED: Memoized filter function
  const filterActivitiesByDate = useCallback(() => {
    setIsFiltering(true);
    try {
      let filtered = [...activityLog];
      if (dateFrom) {
        const fromDate = new Date(dateFrom);
        fromDate.setHours(0, 0, 0, 0);
        filtered = filtered.filter(entry => new Date(entry.timestamp) >= fromDate);
      }
      if (dateTo) {
        const toDate = new Date(dateTo);
        toDate.setHours(23, 59, 59, 999);
        filtered = filtered.filter(entry => new Date(entry.timestamp) <= toDate);
      }
      setFilteredActivities(filtered);
      if (filtered.length === 0) toast('No activities found');
      else toast.success(`Found ${filtered.length} activities`);
    } catch (error) {
      console.error('Error filtering activities:', error);
      toast.error('Failed to filter activities');
    } finally {
      setIsFiltering(false);
    }
  }, [activityLog, dateFrom, dateTo]);

  // ✅ OPTIMIZED: Memoized reset function
  const resetDateFilter = useCallback(() => {
    setDateFrom('');
    setDateTo('');
    setFilteredActivities(activityLog);
    toast('Date filter cleared');
  }, [activityLog]);

  // ✅ OPTIMIZED: Memoized display activities
  const displayActivities = useMemo(() => {
    const activities = showAllActivities ? filteredActivities : activityLog;
    return showAllActivities ? activities : activities.slice(0, 10);
  }, [showAllActivities, filteredActivities, activityLog]);

  // ✅ OPTIMIZED: Core fuel functions with deduplication
  const performFuelDeduction = useCallback(async (fuelType, amount, logEntry) => {
    const dedupKey = `${fuelType}-${amount}-${logEntry.deliveryId || logEntry.saleId || Date.now()}`;
    if (processingQueueRef.current.has(dedupKey)) return;
    processingQueueRef.current.add(dedupKey);

    try {
      if (!fuelType || !amount || amount <= 0) return;

      const result = await validateAndUpdateFuelStock(fuelType, amount, 'remove', logEntry.reason || `Fuel delivery of ${amount}L ${fuelType}`, 'System (Auto)');

      if (result?.success) {
        setTotalStock(prev => ({ ...prev, [fuelType]: result.newAmount }));
        setPreviousStock(prev => ({ ...prev, [fuelType]: result.previousAmount }));
        setAnimate(true);
        setTimeout(() => setAnimate(false), 800);

        const docRef = doc(db, 'company', 'fuelStock');
        const docSnap = await getDoc(docRef);
        if (docSnap.exists()) {
          const data = docSnap.data();
          setActivityLog(data.activityLog || []);
          setFilteredActivities(data.activityLog || []);
        }
        
        toast.success(` ${amount}L ${fuelType} deducted - Remaining: ${result.newAmount.toFixed(1)}L`, { duration: 4000, icon: '📦' });
      }
    } catch (error) {
      console.error('Error performing fuel deduction:', error);
      toast.error(` ${error.message}`);
    } finally {
      setTimeout(() => processingQueueRef.current.delete(dedupKey), 5000);
    }
  }, []);

  const performFuelAddition = useCallback(async (fuelType, amount, logEntry) => {
    const dedupKey = `add-${fuelType}-${amount}-${Date.now()}`;
    if (processingQueueRef.current.has(dedupKey)) return;
    processingQueueRef.current.add(dedupKey);

    try {
      if (!fuelType || !amount || amount <= 0) return;

      const result = await validateAndUpdateFuelStock(fuelType, amount, 'add', logEntry.reason || `Added ${amount}L ${fuelType}`, logEntry.updatedBy || 'Admin');

      if (result?.success) {
        setTotalStock(prev => ({ ...prev, [fuelType]: result.newAmount }));
        setPreviousStock(prev => ({ ...prev, [fuelType]: result.previousAmount }));
        setAnimate(true);
        setTimeout(() => setAnimate(false), 800);

        const docRef = doc(db, 'company', 'fuelStock');
        const docSnap = await getDoc(docRef);
        if (docSnap.exists()) {
          const data = docSnap.data();
          setActivityLog(data.activityLog || []);
          setFilteredActivities(data.activityLog || []);
        }
        
        toast.success(`✅ ${amount}L ${fuelType} added - New total: ${result.newAmount.toFixed(1)}L`, { duration: 4000, icon: '➕' });
      }
    } catch (error) {
      console.error('Error performing fuel addition:', error);
      toast.error(` ${error.message}`);
    } finally {
      setTimeout(() => processingQueueRef.current.delete(dedupKey), 5000);
    }
  }, []);

  // ✅ OPTIMIZED: Single combined listener with cleanup
  useEffect(() => {
    if (loading) return;

    // Cleanup previous listeners
    if (listenerUnsubscribeRef.current) {
      listenerUnsubscribeRef.current();
      listenerUnsubscribeRef.current = null;
    }

    // Listen for fuel deliveries
    const deliveriesQuery = query(collection(db, 'fuelDeliveries'), where('status', '==', 'completed'));
    const unsubscribeDeliveries = onSnapshot(deliveriesQuery, async (snapshot) => {
      const deliveries = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
      setFuelDeliveries(deliveries);

      for (const delivery of deliveries) {
        const deliveryKey = `${delivery.id}-${delivery.fuelType}-${delivery.amount}`;
        if (!processedDeliveries.has(deliveryKey) && delivery.fuelType && delivery.amount) {
          setProcessedDeliveries(prev => new Set([...prev, deliveryKey]));
          
          const logEntry = {
            fuelType: delivery.fuelType,
            amount: delivery.amount,
            action: 'deduct',
            actionType: 'Fuel Delivery',
            reason: `Delivery #${delivery.id} - ${delivery.driverName || 'Driver'} delivered ${delivery.amount}L ${delivery.fuelType}`,
            timestamp: new Date().toISOString(),
            date: new Date().toLocaleString(),
            deliveryId: delivery.id,
            driverName: delivery.driverName || 'Unknown Driver',
            customerName: delivery.customerName || 'Unknown Customer',
            updatedBy: 'System (Auto)',
            truckNumber: delivery.truckNumber || 'N/A'
          };

          await performFuelDeduction(delivery.fuelType, delivery.amount, logEntry);
          
          try {
            await updateDoc(doc(db, 'fuelDeliveries', delivery.id), {
              deductedFromTank: true,
              deductedAt: new Date().toISOString()
            });
          } catch (updateError) {
            console.error(`Error updating delivery ${delivery.id}:`, updateError);
          }
        }
      }
    }, (error) => {
      console.error('Error listening to fuel deliveries:', error);
      toast.error('Failed to listen for fuel deliveries');
    });

    // Listen for sales
    const salesQuery = query(collection(db, 'sales'), where('status', '==', 'completed'));
    const unsubscribeSales = onSnapshot(salesQuery, async (snapshot) => {
      const sales = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));

      for (const sale of sales) {
        if (sale.fuelType && sale.amount && sale.status === 'completed') {
          const saleKey = `sale-${sale.id}-${sale.fuelType}`;
          const alreadyLogged = activityLog.some(log => log.saleId === sale.id && log.action === 'deduct');
          
          if (!processedDeliveries.has(saleKey) && !alreadyLogged) {
            setProcessedDeliveries(prev => new Set([...prev, saleKey]));
            
            const logEntry = {
              fuelType: sale.fuelType,
              amount: sale.amount,
              action: 'deduct',
              actionType: 'Fuel Delivery',
              reason: `Sale #${sale.id} - ${sale.driverName || 'Driver'} delivered ${sale.amount}L ${sale.fuelType}`,
              timestamp: new Date().toISOString(),
              date: new Date().toLocaleString(),
              saleId: sale.id,
              driverName: sale.driverName || 'Unknown Driver',
              customerName: sale.customerName || 'Unknown Customer',
              updatedBy: 'System (Auto)'
            };

            await performFuelDeduction(sale.fuelType, sale.amount, logEntry);
          }
        }
      }
    }, (error) => {
      console.error('Error listening to sales:', error);
    });

    // Listen for company stock updates
    const unsubscribeStock = onSnapshot(doc(db, 'company', 'fuelStock'), (docSnap) => {
      if (docSnap.exists()) {
        const data = docSnap.data();
        const stock = data.stock || { Petrol: 0, Diesel: 0, Kerosene: 0, 'V-Power': 0 };
        
        if (previousStock[selectedFuel] !== undefined) {
          const oldValue = previousStock[selectedFuel] || 0;
          const newValue = stock[selectedFuel] || 0;
          if (Math.abs(newValue - oldValue) > 0.01) {
            setAnimate(true);
            setTimeout(() => setAnimate(false), 800);
          }
        }
        
        setPreviousStock(stock);
        setTotalStock(stock);
        if (data.activityLog) {
          setActivityLog(data.activityLog);
          setFilteredActivities(data.activityLog);
        }
      }
    }, (error) => {
      console.error('Error listening to company stock:', error);
    });

    // Combine unsubscribe functions
    listenerUnsubscribeRef.current = () => {
      unsubscribeDeliveries();
      unsubscribeSales();
      unsubscribeStock();
    };

    return () => {
      if (listenerUnsubscribeRef.current) {
        listenerUnsubscribeRef.current();
        listenerUnsubscribeRef.current = null;
      }
    };
  }, [loading, performFuelDeduction, performFuelAddition, processedDeliveries, activityLog, selectedFuel, previousStock]);

  // ✅ OPTIMIZED: Memoized helper functions
  const getFuelStatus = useCallback((fuelType) => {
    const amount = totalStock[fuelType] || 0;
    const capacity = TANK_CAPACITY[fuelType] || 2000;
    const percentage = Math.min((amount / capacity) * 100, 100);
    
    let status = { color: '', label: '', icon: '' };
    if (percentage >= 100 || amount >= capacity) {
      status = { color: 'text-red-600', label: 'FULL', icon: '🔴' };
    } else if (percentage > 80) {
      status = { color: 'text-green-600', label: 'Full', icon: '🟢' };
    } else if (percentage > 50) {
      status = { color: 'text-yellow-600', label: 'Moderate', icon: '🟡' };
    } else if (percentage > 20) {
      status = { color: 'text-orange-600', label: 'Low', icon: '🟠' };
    } else {
      status = { color: 'text-red-600', label: 'Critical', icon: '🔴' };
    }
    return { percentage, status, amount, capacity };
  }, [totalStock]);

  const getTodayDeliveries = useCallback(() => {
    const today = new Date().toDateString();
    const totalByFuel = {};
    fuelDeliveries.filter(d => new Date(d.createdAt).toDateString() === today).forEach(d => {
      if (d.fuelType) {
        totalByFuel[d.fuelType] = (totalByFuel[d.fuelType] || 0) + (d.amount || 0);
      }
    });
    return totalByFuel;
  }, [fuelDeliveries]);

  // ✅ OPTIMIZED: Memoized tank renderer - View Only (No Edit/Remove)
  const renderFuelTank = useCallback((fuelType) => {
    const { percentage, status, amount, capacity } = getFuelStatus(fuelType);
    const isSelected = fuelType === selectedFuel;
    const liquidHeight = Math.max(5, percentage);
    const isFull = amount >= capacity;
    
    const colorMap = {
      'Petrol': 'from-red-500 via-orange-500 to-yellow-400',
      'Diesel': 'from-green-700 via-green-600 to-green-400',
      'Kerosene': 'from-blue-600 via-indigo-500 to-blue-400',
      'V-Power': 'from-purple-700 via-purple-600 to-purple-400'
    };
    
    const gradientColor = colorMap[fuelType] || 'from-blue-500 to-blue-300';
    const todayDeliveries = getTodayDeliveries();
    const deliveredToday = todayDeliveries[fuelType] || 0;

    return (
      <div key={`tank-${fuelType}`} className={`relative ${isSelected ? 'ring-4 ring-blue-500 ring-opacity-50' : ''}`} onClick={() => setSelectedFuel(fuelType)}>
        <div className={`rounded-xl shadow-lg border ${isFull ? 'border-red-500 border-2' : 'border-gray-200'} p-6 hover:shadow-xl transition-all duration-300 cursor-pointer ${getCardClass()}`}>
          <div className="flex items-center justify-between mb-3">
            <div className="flex items-center space-x-3">
              <div className={`w-4 h-4 rounded-full ${status.color}`}></div>
              <h3 className={`text-lg font-bold ${userBackground === 'dark' ? 'text-white' : 'text-gray-800'}`}>{fuelType}</h3>
              <span className={`text-sm font-medium ${status.color}`}>{status.icon} {status.label}</span>
            </div>
            <div className="text-right">
              <span className={`text-2xl font-bold ${isFull ? 'text-red-600' : userBackground === 'dark' ? 'text-white' : 'text-gray-900'}`}>{amount.toFixed(1)}L</span>
              <span className={`text-sm ml-1 ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>/ {capacity}L</span>
            </div>
          </div>

          {isFull && (
            <div className="mb-2 text-xs text-red-600 bg-red-50 rounded-lg px-3 py-1 font-bold animate-pulse text-center"> TANK IS FULL!</div>
          )}
          {deliveredToday > 0 && (
            <div className="mb-2 text-xs text-blue-600 bg-blue-50 rounded-lg px-3 py-1"> {deliveredToday.toFixed(1)}L delivered today</div>
          )}

          <div className="relative">
            <div className="w-full bg-gray-200 rounded-lg h-48 overflow-hidden border-2 border-gray-300">
              <div className="absolute inset-0 opacity-10">
                <div className="absolute inset-0" style={{ backgroundImage: `repeating-linear-gradient(45deg, transparent, transparent 10px, rgba(0,0,0,0.05) 10px, rgba(0,0,0,0.05) 20px)` }}></div>
              </div>
              
              <div className={`absolute bottom-0 left-0 right-0 transition-all duration-1000 ease-in-out ${animate && fuelType === selectedFuel ? 'animate-pulse-slow' : ''}`} style={{ height: `${Math.min(liquidHeight, 100)}%` }}>
                <div className={`w-full h-full bg-gradient-to-t ${gradientColor} relative overflow-hidden`}>
                  <div className="absolute inset-0 opacity-30">
                    <div className="absolute inset-0 animate-wave" style={{ background: `repeating-linear-gradient(90deg, transparent, transparent 20px, rgba(255,255,255,0.1) 20px, rgba(255,255,255,0.1) 40px)` }}></div>
                  </div>
                  <div className="absolute top-0 left-0 right-0 h-8 bg-gradient-to-b from-white/30 to-transparent animate-shimmer"></div>
                </div>
              </div>

              <div className="absolute inset-0 flex items-center justify-center">
                <div className="bg-black/40 backdrop-blur-sm rounded-lg px-4 py-2">
                  <span className={`text-2xl font-bold ${percentage > 50 ? 'text-white' : 'text-gray-200'}`}>{percentage.toFixed(1)}%</span>
                </div>
              </div>

              <div className="absolute right-2 top-2 bottom-2 flex flex-col justify-between text-xs text-gray-400">
                <span>100%</span><span>75%</span><span>50%</span><span>25%</span><span>0%</span>
              </div>
            </div>
          </div>

          {/* View Only Stats - No Edit Button */}
          <div className="grid grid-cols-2 gap-2 mt-4">
            <div className={`rounded-lg p-2 text-center ${userBackground === 'dark' ? 'bg-gray-700/50' : 'bg-gray-50'}`}>
              <p className={`text-xs ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>Available</p>
              <p className={`font-bold ${isFull ? 'text-red-600' : userBackground === 'dark' ? 'text-white' : 'text-gray-900'}`}>{amount.toFixed(1)}L</p>
            </div>
            <div className={`rounded-lg p-2 text-center ${userBackground === 'dark' ? 'bg-gray-700/50' : 'bg-gray-50'}`}>
              <p className={`text-xs ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>Capacity</p>
              <p className={`font-bold ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'}`}>{capacity}L</p>
            </div>
          </div>
          
          {/* Info Message */}
          <div className="mt-3 text-center">
            <p className={`text-xs ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-400'} border-t ${userBackground === 'dark' ? 'border-gray-700' : 'border-gray-100'} pt-2`}>
               Fuel is managed through imports and deliveries only
            </p>
          </div>
        </div>
      </div>
    );
  }, [getFuelStatus, selectedFuel, animate, getTodayDeliveries, userBackground, getCardClass]);

  if (loading) {
    return (
      <div className={`min-h-screen flex items-center justify-center ${getBackgroundClass()}`}>
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-green-500"></div>
      </div>
    );
  }

  const totalActivities = showAllActivities ? filteredActivities.length : Math.min(10, activityLog.length);
  const hasMoreActivities = activityLog.length > 10;

  return (
    <div className={`min-h-screen p-4 md:p-6 transition-colors duration-300 ${getBackgroundClass()}`}>
      <div className="max-w-7xl mx-auto space-y-6">
        {/* Header */}
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <div>
            <h1 className="text-2xl font-bold">  Fuel Tanks</h1>
            <p className={`text-sm mt-1 ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>
              Real-time fuel stock levels with AI tank visualization
            </p>
          </div>
          <Link href="/fuel" className={`text-sm ${userBackground === 'dark' ? 'text-gray-400 hover:text-gray-200' : 'text-gray-500 hover:text-gray-700'} flex items-center space-x-1`}>
            <span>←</span>
            <span>Back to Fuel</span>
          </Link>
        </div>

        {/* Summary Cards */}
<div className="grid grid-cols-2 md:grid-cols-4 gap-4">
  {Object.keys(totalStock).map((fuelType) => {
    const { percentage, status } = getFuelStatus(fuelType);
    const isFull = totalStock[fuelType] >= TANK_CAPACITY[fuelType];
    const todayDeliveries = getTodayDeliveries();
    const deliveredToday = todayDeliveries[fuelType] || 0;
    
    return (
      <div key={`summary-${fuelType}`} className={`rounded-lg shadow p-4 border ${isFull ? 'border-red-500' : 'border-gray-200'} ${
        fuelType === 'Diesel' ? 'bg-green-500' :
        fuelType === 'Kerosene' ? 'bg-blue-500' :
        fuelType === 'Petrol' ? 'bg-red-500' :
        fuelType === 'V-Power' ? 'bg-purple-500' :
        'bg-white'
      }`}>
        <p className="text-sm text-gray-600">{fuelType}</p>
        <p className={`text-xl font-bold ${isFull ? 'text-red-600' : 'text-gray-900'}`}>{totalStock[fuelType].toFixed(1)}L</p>
        <div className="flex items-center mt-1">
          <div className="w-full bg-gray-200 rounded-full h-2">
            <div className={`h-2 rounded-full ${isFull ? 'bg-red-500' : percentage > 80 ? 'bg-green-500' : percentage > 50 ? 'bg-yellow-500' : percentage > 20 ? 'bg-orange-500' : 'bg-red-500'}`} style={{ width: `${Math.min(percentage, 100)}%` }} />
          </div>
          <span className="text-xs ml-2 text-gray-500">{percentage.toFixed(0)}%</span>
        </div>
        {isFull && <p className="text-xs text-red-600 mt-1 font-bold animate-pulse"> FULL</p>}
        {deliveredToday > 0 && <p className="text-xs text-blue-600 mt-1"> {deliveredToday.toFixed(1)}L today</p>}
      </div>
    );
  })}
</div>

        {/* Fuel Tank Visualizations - View Only */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          {Object.keys(totalStock).map((fuelType) => renderFuelTank(fuelType))}
        </div>

        {/* Activity Log */}
        {activityLog.length > 0 && (
          <div className={`rounded-xl shadow-sm p-6 border ${userBackground === 'dark' ? 'border-gray-700' : 'border-gray-200'} ${getCardClass()}`}>
            <div className="flex items-center justify-between mb-4">
              <h2 className={`text-lg font-semibold ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'}`}>
                 Activity Log 
                <span className={`text-sm font-normal ml-2 ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>
                  ({totalActivities} of {activityLog.length} activities)
                </span>
              </h2>
              {hasMoreActivities && (
                <button onClick={() => setShowAllActivities(!showAllActivities)} className="text-sm text-blue-600 hover:text-blue-800 font-medium transition">
                  {showAllActivities ? 'Show Less' : 'See All Activities'}
                </button>
              )}
            </div>

            {showAllActivities && (
              <div className={`mb-4 p-4 rounded-lg border ${userBackground === 'dark' ? 'border-gray-700 bg-gray-800/50' : 'border-gray-200 bg-gray-50'}`}>
                <div className="flex flex-wrap items-end gap-3">
                  <div>
                    <label className={`block text-xs font-medium ${userBackground === 'dark' ? 'text-gray-400' : 'text-red-800'} mb-1`}>Date From</label>
                    <input type="date" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} className={`px-3 py-1.5 border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'}`} />
                  </div>
                  <div>
                    <label className={`block text-xs font-medium ${userBackground === 'dark' ? 'text-gray-500' : 'text-red-800'} mb-1`}>Date To</label>
                    <input type="date" value={dateTo} onChange={(e) => setDateTo(e.target.value)} className={`px-3 py-1.5 border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'}`} />
                  </div>
                  <button onClick={filterActivitiesByDate} disabled={isFiltering || (!dateFrom && !dateTo)} className={`px-4 py-1.5 text-sm font-medium text-white rounded-lg transition ${isFiltering || (!dateFrom && !dateTo) ? 'bg-gray-400 cursor-not-allowed' : 'bg-blue-500 hover:bg-blue-600'}`}>
                    {isFiltering ? 'Filtering...' : 'Filter'}
                  </button>
                  {(dateFrom || dateTo) && (
                    <button onClick={resetDateFilter} className={`px-4 py-1.5 text-sm font-medium rounded-lg transition ${userBackground === 'dark' ? 'text-gray-300 bg-gray-700 hover:bg-gray-600' : 'text-gray-700 bg-gray-200 hover:bg-gray-300'}`}>Clear</button>
                  )}
                </div>
              </div>
            )}

            <div className="max-h-96 overflow-y-auto">
              <div className="space-y-2">
                {displayActivities.length > 0 ? (
                  displayActivities.map((entry, index) => (
                    <div key={`log-${index}`} className={`flex items-center justify-between p-3 rounded-lg text-sm ${userBackground === 'dark' ? 'bg-gray-800/50' : 'bg-gray-50'}`}>
                      <div className="flex items-center space-x-3">
                        <span className={`px-2 py-1 rounded-full text-xs font-medium ${entry.action === 'add' ? 'bg-green-100 text-green-700' : entry.action === 'deduct' ? 'bg-blue-100 text-blue-700' : 'bg-red-100 text-red-700'}`}>
                          {entry.action === 'add' ? ' Added' : entry.action === 'deduct' ? ' Delivered' : ' Removed'}
                        </span>
                        <span className={userBackground === 'dark' ? 'text-gray-300' : 'text-gray-600'}>
                          {entry.actionType}: {entry.amount}L {entry.fuelType}
                          {entry.reason && ` - ${entry.reason}`}
                          {entry.driverName && ` (${entry.driverName})`}
                          {entry.previousTankAmount !== undefined && (
                            <span className={`text-xs ml-2 ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-400'}`}>Tank: {entry.previousTankAmount.toFixed(1)}L → {entry.newTankAmount.toFixed(1)}L</span>
                          )}
                          {entry.capacityInfo && (
                            <span className="text-xs text-purple-600 ml-2 font-medium"> {entry.capacityInfo}</span>
                          )}
                        </span>
                      </div>
                      <span className={`text-xs ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-400'}`}>{entry.date}</span>
                    </div>
                  ))
                ) : (
                  <div className={`text-center py-8 ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>No activities found</div>
                )}
              </div>
            </div>
          </div>
        )}

        {/* Legend */}
        <div className={`rounded-lg p-4 border ${userBackground === 'dark' ? 'border-gray-700 bg-gray-800/50' : 'border-blue-200 bg-blue-50'}`}>
          <div className="flex flex-wrap items-center justify-between gap-2">
            <div className="flex items-center space-x-4">
              <span className={`text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-blue-800'}`}> Legend:</span>
              <span className={`text-sm ${userBackground === 'dark' ? 'text-gray-300' : 'text-blue-700'}`}>🟢 Full (80%+)</span>
              <span className={`text-sm ${userBackground === 'dark' ? 'text-gray-300' : 'text-blue-700'}`}>🟡 Moderate (50-80%)</span>
              <span className={`text-sm ${userBackground === 'dark' ? 'text-gray-300' : 'text-blue-700'}`}>🟠 Low (20-50%)</span>
              <span className={`text-sm ${userBackground === 'dark' ? 'text-gray-300' : 'text-blue-700'}`}>🔴 Critical (0-20%)</span>
            </div>
            <div className={`text-sm ${userBackground === 'dark' ? 'text-gray-300' : 'text-blue-700'}`}>💡 Fuel is auto-deducted when drivers complete deliveries</div>
          </div>
        </div>
      </div>

      {/* CSS Animations */}
      <style jsx>{`
        @keyframes wave { 0% { transform: translateX(-100%) rotate(0deg); } 100% { transform: translateX(100%) rotate(0deg); } }
        @keyframes shimmer { 0% { opacity: 0.3; } 50% { opacity: 0.6; } 100% { opacity: 0.3; } }
        @keyframes pulse-slow { 0% { opacity: 1; } 50% { opacity: 0.9; } 100% { opacity: 1; } }
        @keyframes pulse { 0% { opacity: 1; } 50% { opacity: 0.5; } 100% { opacity: 1; } }
        .animate-wave { animation: wave 4s linear infinite; }
        .animate-shimmer { animation: shimmer 3s ease-in-out infinite; }
        .animate-pulse-slow { animation: pulse-slow 1s ease-in-out; }
        .animate-pulse { animation: pulse 1.5s ease-in-out infinite; }
      `}</style>
    </div>
  );
}