'use client';

import { useState, useEffect, useRef } from 'react';
import { db, auth } from '../../../lib/firebase';
import { collection, getDocs, doc, getDoc, onSnapshot } from 'firebase/firestore';
import toast from 'react-hot-toast';
import Link from 'next/link';
import Image from 'next/image';

export default function ComprehensiveReport() {
  const [salesData, setSalesData] = useState([]);
  const [driversData, setDriversData] = useState([]);
  const [fuelStockData, setFuelStockData] = useState({});
  const [totalLitresWithDrivers, setTotalLitresWithDrivers] = useState(0);
  const [importData, setImportData] = useState([]);
  const [loading, setLoading] = useState(true);
  const [userBackground, setUserBackground] = useState('white');
  const [password, setPassword] = useState('');
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [passwordError, setPasswordError] = useState('');

  // Stats states
  const [totalStats, setTotalStats] = useState({
    revenue: 0,
    litres: 0,
    orders: 0
  });
  const [weeklyStats, setWeeklyStats] = useState({
    revenue: 0,
    litres: 0,
    orders: 0,
    startDate: '',
    endDate: ''
  });
  const [monthlyStats, setMonthlyStats] = useState({
    revenue: 0,
    litres: 0,
    orders: 0,
    startDate: '',
    endDate: ''
  });
  const [yearlyStats, setYearlyStats] = useState({
    revenue: 0,
    litres: 0,
    orders: 0,
    startDate: '',
    endDate: ''
  });
  const [todayStats, setTodayStats] = useState({
    revenue: 0,
    litres: 0,
    orders: 0
  });

  // Daily Activity State
  const [dailyActivities, setDailyActivities] = useState([]);
  const [selectedDate, setSelectedDate] = useState('');
  const [dailyDateFrom, setDailyDateFrom] = useState('');
  const [dailyDateTo, setDailyDateTo] = useState('');
  const [filteredDailyActivities, setFilteredDailyActivities] = useState([]);
  const [showDailyFiltered, setShowDailyFiltered] = useState(false);
  const [dailyLastUpdate, setDailyLastUpdate] = useState(null);

  // Import Fuel Filter States
  const [importDateFrom, setImportDateFrom] = useState('');
  const [importDateTo, setImportDateTo] = useState('');
  const [filteredImports, setFilteredImports] = useState([]);
  const [showImportFiltered, setShowImportFiltered] = useState(false);

  // Drivers Search State
  const [searchDriverTerm, setSearchDriverTerm] = useState('');
  const [filteredDrivers, setFilteredDrivers] = useState([]);
  const [isLiveUpdate, setIsLiveUpdate] = useState(false);
  const [lastUpdateTime, setLastUpdateTime] = useState(new Date());
  
  // Search state for Individual Driver Fuel Breakdown table
  const [fuelBreakdownSearchTerm, setFuelBreakdownSearchTerm] = useState('');
  const [filteredFuelBreakdown, setFilteredFuelBreakdown] = useState([]);
  
  // Selected driver for fuel movement history
  const [selectedDriverId, setSelectedDriverId] = useState(null);
  const [selectedDriverHistory, setSelectedDriverHistory] = useState([]);
  const [showDriverHistory, setShowDriverHistory] = useState(false);
  
  // Use ref for unsubscribe to avoid stale closure
  const driversUnsubscribeRef = useRef(null);

  // Date filter states
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');
  const [filteredSales, setFilteredSales] = useState([]);
  const [isFiltering, setIsFiltering] = useState(false);
  const [showFilteredReport, setShowFilteredReport] = useState(false);

  // Section navigation state
  const [activeSection, setActiveSection] = useState('revenue');

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

  // Update filtered drivers whenever driversData changes
  useEffect(() => {
    if (searchDriverTerm.trim() !== '') {
      const searchTerm = searchDriverTerm.toLowerCase();
      const filtered = driversData.filter(driver => {
        const nameMatch = driver.name?.toLowerCase().includes(searchTerm);
        const phoneMatch = driver.phone?.toLowerCase().includes(searchTerm);
        return nameMatch || phoneMatch;
      });
      setFilteredDrivers(filtered);
    } else {
      setFilteredDrivers(driversData);
    }
  }, [driversData, searchDriverTerm]);

  // Filter fuel breakdown drivers whenever driversData or search term changes
  useEffect(() => {
    if (fuelBreakdownSearchTerm.trim() !== '') {
      const searchTerm = fuelBreakdownSearchTerm.toLowerCase();
      const filtered = driversData.filter(driver => {
        const nameMatch = driver.name?.toLowerCase().includes(searchTerm);
        const phoneMatch = driver.phone?.toLowerCase().includes(searchTerm);
        return nameMatch || phoneMatch;
      });
      setFilteredFuelBreakdown(filtered);
    } else {
      setFilteredFuelBreakdown(driversData);
    }
  }, [driversData, fuelBreakdownSearchTerm]);

  // Set up real-time listener
  const setupDriversListener = () => {
    if (driversUnsubscribeRef.current) {
      console.log('🧹 Cleaning up existing listener...');
      driversUnsubscribeRef.current();
      driversUnsubscribeRef.current = null;
    }

    console.log(' Setting up real-time driver listener with useRef...');

    const unsubscribe = onSnapshot(collection(db, 'drivers'), (snapshot) => {
      console.log(' Real-time update received! Drivers changed.');
      
      const driversList = [];
      let totalStock = { Petrol: 0, Diesel: 0, Kerosene: 0, 'V-Power': 0 };
      const allSales = [];

      snapshot.docs.forEach(doc => {
        const data = doc.data();
        const driverId = doc.id;
        
        driversList.push({ id: driverId, ...data });
        
        if (data.remainingFuel) {
          Object.entries(data.remainingFuel).forEach(([key, val]) => {
            totalStock[key] = (totalStock[key] || 0) + (val || 0);
          });
        }

        if (data.salesHistory) {
          data.salesHistory.forEach(sale => {
            allSales.push({
              ...sale,
              driverId: driverId,
              driverName: data.name
            });
          });
        }
      });

      const totalCombinedLitres = Object.values(totalStock).reduce((sum, val) => sum + val, 0);

      setDriversData(driversList);
      setFuelStockData(totalStock);
      setTotalLitresWithDrivers(totalCombinedLitres);
      setIsLiveUpdate(true);
      setLastUpdateTime(new Date());
      
      const sortedSales = allSales.sort((a, b) =>
        new Date(b.date) - new Date(a.date)
      );
      setSalesData(sortedSales);
      calculateStats(sortedSales);
      
      const today = new Date();
      const todayStr = today.toISOString().split('T')[0];
      
      const dateToFilter = selectedDate || todayStr;
      filterDailyActivities(sortedSales, dateToFilter);
      
      if (!selectedDate) {
        setSelectedDate(todayStr);
      }
      
      if (showDailyFiltered && (dailyDateFrom || dailyDateTo)) {
        filterDailyActivitiesByDate(sortedSales);
      }
      
      setDailyLastUpdate(new Date());

      fetchImports();
      setLoading(false);
      
      const onlineDrivers = driversList.filter(d => d.isOnline === true).length;
      const offlineDrivers = driversList.length - onlineDrivers;
      console.log(`🟢 Online drivers: ${onlineDrivers} | 🔴 Offline drivers: ${offlineDrivers} | Total: ${driversList.length}`);
      console.log(` Total fuel with drivers: ${totalCombinedLitres}L (${Object.entries(totalStock).map(([k,v]) => `${k}: ${v}L`).join(', ')})`);
      
      toast.success(` Driver status updated: ${onlineDrivers} online, ${offlineDrivers} offline`, { duration: 2000 });
      
    }, (error) => {
      console.error('❌ Error listening to drivers:', error);
      toast.error('Failed to load real-time driver data');
    });

    driversUnsubscribeRef.current = unsubscribe;
    console.log('✅ Real-time driver listener connected!');
  };

  // Fetch imports separately
  const fetchImports = async () => {
    try {
      const importsSnapshot = await getDocs(collection(db, 'fuelImports'));
      const importsList = [];
      importsSnapshot.docs.forEach(doc => {
        importsList.push({ id: doc.id, ...doc.data() });
      });
      const sortedImports = importsList.sort((a, b) => {
        const dateA = a.date ? new Date(a.date) : new Date(0);
        const dateB = b.date ? new Date(b.date) : new Date(0);
        return dateB - dateA;
      });
      setImportData(sortedImports);
      setFilteredImports(sortedImports);
    } catch (error) {
      console.log('No fuel imports collection found');
      setImportData([]);
      setFilteredImports([]);
    }
  };

  async function fetchAllData() {
    setLoading(true);
    try {
      const driversSnapshot = await getDocs(collection(db, 'drivers'));
      const driversList = [];
      let totalStock = { Petrol: 0, Diesel: 0, Kerosene: 0, 'V-Power': 0 };
      const allSales = [];

      driversSnapshot.docs.forEach(doc => {
        const data = doc.data();
        const driverId = doc.id;
        driversList.push({ id: driverId, ...data });
        
        if (data.remainingFuel) {
          Object.entries(data.remainingFuel).forEach(([key, val]) => {
            totalStock[key] = (totalStock[key] || 0) + (val || 0);
          });
        }

        if (data.salesHistory) {
          data.salesHistory.forEach(sale => {
            allSales.push({
              ...sale,
              driverId: driverId,
              driverName: data.name
            });
          });
        }
      });

      const totalCombinedLitres = Object.values(totalStock).reduce((sum, val) => sum + val, 0);

      const sortedSales = allSales.sort((a, b) =>
        new Date(b.date) - new Date(a.date)
      );

      setSalesData(sortedSales);
      setDriversData(driversList);
      setFilteredDrivers(driversList);
      setFilteredFuelBreakdown(driversList);
      setFuelStockData(totalStock);
      setTotalLitresWithDrivers(totalCombinedLitres);
      calculateStats(sortedSales);
      
      const today = new Date();
      const todayStr = today.toISOString().split('T')[0];
      setSelectedDate(todayStr);
      filterDailyActivities(sortedSales, todayStr);

      await fetchImports();

    } catch (error) {
      console.error('Error fetching data:', error);
      toast.error('Failed to load data');
    } finally {
      setLoading(false);
    }
  }

  // Initialize data and listener
  useEffect(() => {
    fetchAllData();
    setupDriversListener();
    
    return () => {
      if (driversUnsubscribeRef.current) {
        console.log('🧹 Cleaning up listener on unmount...');
        driversUnsubscribeRef.current();
        driversUnsubscribeRef.current = null;
      }
    };
  }, []);

  function calculateStats(sales) {
    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    
    const totalRevenue = sales.reduce((sum, sale) => sum + (sale.totalAmount || 0), 0);
    const totalLitres = sales.reduce((sum, sale) => sum + (sale.litresSold || 0), 0);
    
    setTotalStats({
      revenue: totalRevenue,
      litres: totalLitres,
      orders: sales.length
    });

    const todaySales = sales.filter(sale => {
      const saleDate = new Date(sale.date);
      return saleDate.toDateString() === today.toDateString();
    });

    setTodayStats({
      revenue: todaySales.reduce((sum, sale) => sum + (sale.totalAmount || 0), 0),
      litres: todaySales.reduce((sum, sale) => sum + (sale.litresSold || 0), 0),
      orders: todaySales.length
    });

    const currentDay = today.getDay();
    const daysToMonday = currentDay === 0 ? 6 : currentDay - 1;
    const weekStart = new Date(today);
    weekStart.setDate(today.getDate() - daysToMonday);
    weekStart.setHours(0, 0, 0, 0);
    
    const weekEnd = new Date(weekStart);
    weekEnd.setDate(weekStart.getDate() + 6);
    weekEnd.setHours(23, 59, 59, 999);

    const weeklySales = sales.filter(sale => {
      const saleDate = new Date(sale.date);
      return saleDate >= weekStart && saleDate <= weekEnd;
    });

    setWeeklyStats({
      revenue: weeklySales.reduce((sum, sale) => sum + (sale.totalAmount || 0), 0),
      litres: weeklySales.reduce((sum, sale) => sum + (sale.litresSold || 0), 0),
      orders: weeklySales.length,
      startDate: weekStart.toLocaleDateString(),
      endDate: weekEnd.toLocaleDateString()
    });

    const monthStart = new Date(today.getFullYear(), today.getMonth(), 1);
    monthStart.setHours(0, 0, 0, 0);
    
    const monthEnd = new Date(today.getFullYear(), today.getMonth() + 1, 0);
    monthEnd.setHours(23, 59, 59, 999);

    const monthlySales = sales.filter(sale => {
      const saleDate = new Date(sale.date);
      return saleDate >= monthStart && saleDate <= monthEnd;
    });

    setMonthlyStats({
      revenue: monthlySales.reduce((sum, sale) => sum + (sale.totalAmount || 0), 0),
      litres: monthlySales.reduce((sum, sale) => sum + (sale.litresSold || 0), 0),
      orders: monthlySales.length,
      startDate: monthStart.toLocaleDateString(),
      endDate: monthEnd.toLocaleDateString()
    });

    const yearStart = new Date(today.getFullYear(), 0, 1);
    yearStart.setHours(0, 0, 0, 0);
    
    const yearEnd = new Date(today.getFullYear(), 11, 31);
    yearEnd.setHours(23, 59, 59, 999);

    const yearlySales = sales.filter(sale => {
      const saleDate = new Date(sale.date);
      return saleDate >= yearStart && saleDate <= yearEnd;
    });

    setYearlyStats({
      revenue: yearlySales.reduce((sum, sale) => sum + (sale.totalAmount || 0), 0),
      litres: yearlySales.reduce((sum, sale) => sum + (sale.litresSold || 0), 0),
      orders: yearlySales.length,
      startDate: yearStart.toLocaleDateString(),
      endDate: yearEnd.toLocaleDateString()
    });
  }

  function filterDailyActivitiesByDate(salesDataParam = null) {
    const data = salesDataParam || salesData;
    
    if (!dailyDateFrom && !dailyDateTo) {
      toast.error('Please select a date range');
      return;
    }

    let filtered = [...data];

    if (dailyDateFrom) {
      const fromDate = new Date(dailyDateFrom);
      fromDate.setHours(0, 0, 0, 0);
      filtered = filtered.filter(entry => {
        const entryDate = new Date(entry.date);
        return entryDate >= fromDate;
      });
    }

    if (dailyDateTo) {
      const toDate = new Date(dailyDateTo);
      toDate.setHours(23, 59, 59, 999);
      filtered = filtered.filter(entry => {
        const entryDate = new Date(entry.date);
        return entryDate <= toDate;
      });
    }

    setFilteredDailyActivities(filtered);
    setShowDailyFiltered(true);
    setDailyLastUpdate(new Date());

    if (filtered.length === 0) {
      toast('No activities found for the selected date range');
    } else {
      toast.success(`Found ${filtered.length} activities`);
    }
  }

  const resetDailyFilter = () => {
    setDailyDateFrom('');
    setDailyDateTo('');
    setFilteredDailyActivities([]);
    setShowDailyFiltered(false);
    if (selectedDate) {
      filterDailyActivities(salesData, selectedDate);
    }
    toast('Daily filter cleared');
  };

  function filterImportsByDate() {
    if (!importDateFrom && !importDateTo) {
      toast.error('Please select a date range');
      return;
    }

    let filtered = [...importData];

    if (importDateFrom) {
      const fromDate = new Date(importDateFrom);
      fromDate.setHours(0, 0, 0, 0);
      filtered = filtered.filter(entry => {
        const entryDate = new Date(entry.date);
        return entryDate >= fromDate;
      });
    }

    if (importDateTo) {
      const toDate = new Date(importDateTo);
      toDate.setHours(23, 59, 59, 999);
      filtered = filtered.filter(entry => {
        const entryDate = new Date(entry.date);
        return entryDate <= toDate;
      });
    }

    setFilteredImports(filtered);
    setShowImportFiltered(true);

    if (filtered.length === 0) {
      toast('No imports found for the selected date range');
    } else {
      toast.success(`Found ${filtered.length} imports`);
    }
  }

  const resetImportFilter = () => {
    setImportDateFrom('');
    setImportDateTo('');
    setFilteredImports([]);
    setShowImportFiltered(false);
    toast('Import filter cleared');
  };

  function filterDailyActivities(sales, date) {
    if (!date) return;
    
    const filtered = sales.filter(sale => {
      const saleDate = new Date(sale.date);
      const filterDate = new Date(date);
      return saleDate.toDateString() === filterDate.toDateString();
    });
    setDailyActivities(filtered);
    setDailyLastUpdate(new Date());
    console.log(`📊 Daily activities updated for ${date}: ${filtered.length} activities found`);
  }

  const handleDateChange = (e) => {
    const date = e.target.value;
    setSelectedDate(date);
    filterDailyActivities(salesData, date);
    setShowDailyFiltered(false);
    setFilteredDailyActivities([]);
  };

  const handleDriverSearch = (term) => {
    setSearchDriverTerm(term);
  };

  const filterSalesByDate = () => {
    if (!dateFrom && !dateTo) {
      toast.error('Please select a date range');
      return;
    }

    setIsFiltering(true);
    try {
      let filtered = [...salesData];

      if (dateFrom) {
        const fromDate = new Date(dateFrom);
        fromDate.setHours(0, 0, 0, 0);
        filtered = filtered.filter(entry => {
          const entryDate = new Date(entry.date);
          return entryDate >= fromDate;
        });
      }

      if (dateTo) {
        const toDate = new Date(dateTo);
        toDate.setHours(23, 59, 59, 999);
        filtered = filtered.filter(entry => {
          const entryDate = new Date(entry.date);
          return entryDate <= toDate;
        });
      }

      setFilteredSales(filtered);
      setShowFilteredReport(true);

      if (filtered.length === 0) {
        toast('No sales found for the selected date range');
      } else {
        toast.success(`Found ${filtered.length} sales transactions`);
      }
    } catch (error) {
      console.error('Error filtering sales:', error);
      toast.error('Failed to filter sales');
    } finally {
      setIsFiltering(false);
    }
  };

  const resetDateFilter = () => {
    setDateFrom('');
    setDateTo('');
    setFilteredSales([]);
    setShowFilteredReport(false);
    toast('Date filter cleared');
  };

  const handlePasswordSubmit = (e) => {
    e.preventDefault();
    if (password === '1234') {
      setIsAuthenticated(true);
      setPasswordError('');
      toast.success('Access granted');
    } else {
      setPasswordError('Incorrect password. Please try again.');
      toast.error('Incorrect password');
    }
  };

  // ✅ FIXED: Calculate driver fuel metrics using fuelHistory for depot top-ups
  const calculateDriverMetrics = (driver) => {
    const remaining = driver.remainingFuel || {};
    const totalRemaining = Object.values(remaining).reduce((sum, val) => sum + (val || 0), 0);
    
    // Get fuel types from remaining fuel
    const fuelTypes = Object.keys(remaining);
    
    // Use fuelHistory for depot top-ups
    const fuelHistory = driver.fuelHistory || [];
    const salesHistory = driver.salesHistory || [];
    
    // ✅ FIX: Determine primary fuel type from fuelHistory first (most recent top-up)
    let primaryFuelType = 'Petrol'; // Default to Petrol
    
    if (fuelHistory.length > 0) {
      // Sort fuelHistory by timestamp (newest first)
      const sortedFuelHistoryForType = [...fuelHistory].sort((a, b) => {
        const dateA = new Date(a.timestamp);
        const dateB = new Date(b.timestamp);
        return dateB - dateA;
      });
      
      // Get fuel type from the most recent fuel history entry
      const mostRecentFuel = sortedFuelHistoryForType[0];
      if (mostRecentFuel && mostRecentFuel.fuelType) {
        primaryFuelType = mostRecentFuel.fuelType;
      }
    } else if (fuelTypes.length > 0) {
      // If no fuel history, use remaining fuel types
      primaryFuelType = fuelTypes[0];
    }
    
    // ✅ ACCURATE: Sort fuelHistory by timestamp (newest first)
    const sortedFuelHistory = [...fuelHistory].sort((a, b) => {
      const dateA = new Date(a.timestamp);
      const dateB = new Date(b.timestamp);
      return dateB - dateA;
    });
    
    // ✅ ACCURATE: Sort salesHistory by date (newest first)
    const sortedSalesHistory = [...salesHistory].sort((a, b) => {
      const dateA = new Date(a.date);
      const dateB = new Date(b.date);
      return dateB - dateA;
    });
    
    // Total depot top-ups = number of fuelHistory entries
    const totalDepotTopUps = sortedFuelHistory.length;
    
    // Total litres added at depot = sum of all fuelHistory amounts
    const totalDepotLitresAdded = sortedFuelHistory.reduce((sum, entry) => sum + (entry.amount || 0), 0);
    
    // Total litres sold to customers = sum of all salesHistory
    const totalLitresSoldToCustomers = sortedSalesHistory.reduce((sum, sale) => sum + (sale.litresSold || 0), 0);
    
    // ✅ CORRECT: Last Depot Top Up = most recent entry in fuelHistory
    const lastDepotTopUp = sortedFuelHistory.length > 0 ? sortedFuelHistory[0] : null;
    const lastDepotTopUpDate = lastDepotTopUp?.timestamp || null;
    const lastDepotTopUpLitres = lastDepotTopUp?.amount || 0;
    
    // ✅ FIX: Use the fuel type from the top-up, fallback to Petrol
    const lastDepotTopUpFuelType = lastDepotTopUp?.fuelType || 'Petrol';
    const lastDepotTopUpAdmin = lastDepotTopUp?.adminName || 'Admin';
    const lastDepotTopUpNote = lastDepotTopUp?.note || '';
    const lastDepotTopUpSource = lastDepotTopUp?.source || 'main-tank';
    const mainTankBefore = lastDepotTopUp?.mainTankBefore || 0;
    const mainTankAfter = lastDepotTopUp?.mainTankAfter || 0;
    
    // ✅ ACCURATE: Calculate sold since last depot top-up
    let soldSinceLastTopUp = 0;
    let salesSinceLastTopUp = [];
    let customersServedSinceTopUp = 0;
    if (lastDepotTopUpDate) {
      const lastTopUpTime = new Date(lastDepotTopUpDate).getTime();
      salesSinceLastTopUp = sortedSalesHistory.filter(sale => {
        const saleTime = new Date(sale.date).getTime();
        return saleTime >= lastTopUpTime;
      });
      soldSinceLastTopUp = salesSinceLastTopUp.reduce((sum, sale) => sum + (sale.litresSold || 0), 0);
      customersServedSinceTopUp = salesSinceLastTopUp.length;
    }
    
    // ✅ ACCURATE: Calculate days since last depot top-up
    let daysSinceTopUp = 'N/A';
    let daysSinceTopUpNumber = 0;
    if (lastDepotTopUpDate) {
      const diffTime = new Date().getTime() - new Date(lastDepotTopUpDate).getTime();
      const diffDays = diffTime / (1000 * 60 * 60 * 24);
      daysSinceTopUpNumber = diffDays;
      daysSinceTopUp = diffDays < 1 ? 'Today' : `${Math.floor(diffDays)}d ${Math.floor((diffDays % 1) * 24)}h`;
    }
    
    // ✅ ACCURATE: Calculate average litres sold per day since last top-up
    let avgSoldPerDay = 0;
    if (lastDepotTopUpDate && soldSinceLastTopUp > 0 && daysSinceTopUpNumber > 0) {
      avgSoldPerDay = Math.round((soldSinceLastTopUp / daysSinceTopUpNumber) * 100) / 100;
    } else if (soldSinceLastTopUp > 0) {
      avgSoldPerDay = soldSinceLastTopUp;
    }
    
    // ✅ ACCURATE: Calculate current fuel remaining
    const currentFuelRemaining = totalRemaining;
    
    // ✅ ACCURATE: Fuel needed for refill
    const tankCapacity = driver.tankCapacity || 200;
    const fuelNeeded = Math.max(0, tankCapacity - currentFuelRemaining);
    
    // ✅ ACCURATE: Remaining percentage
    const remainingPercent = tankCapacity > 0 ? Math.round((currentFuelRemaining / tankCapacity) * 100) : 0;
    
    // ✅ ACCURATE: Refill status based on remaining percentage
    let refillStatus = '🟢 Good';
    let refillStatusColor = 'text-green-600 bg-green-50 border-green-200';
    if (remainingPercent <= 10) {
      refillStatus = '🔴 Critical - Refill Immediately';
      refillStatusColor = 'text-red-600 bg-red-50 border-red-200';
    } else if (remainingPercent <= 25) {
      refillStatus = '🟠 Low - Refill Soon';
      refillStatusColor = 'text-orange-600 bg-orange-50 border-orange-200';
    } else if (remainingPercent <= 50) {
      refillStatus = '🟡 Moderate';
      refillStatusColor = 'text-yellow-600 bg-yellow-50 border-yellow-200';
    }
    
    // Get last customer sale
    const lastCustomerSale = sortedSalesHistory.length > 0 ? sortedSalesHistory[0] : null;
    const lastSaleDate = lastCustomerSale?.date || null;
    const lastSaleLitres = lastCustomerSale?.litresSold || 0;
    const lastSaleFuelType = lastCustomerSale?.fuelType || '';
    const lastSaleAmount = lastCustomerSale?.totalAmount || 0;
    
    // Status
    const isOnline = driver.isOnline === true;
    const status = isOnline ? 'Online' : 'Offline';
    
    // ✅ ACCURATE: Build trip cycles from fuelHistory
    const tripCycles = [];
    sortedFuelHistory.forEach((topUp, index) => {
      const cycleStartDate = topUp.timestamp;
      const cycleStartLitres = topUp.amount;
      
      // Find sales that occurred after this top-up and before the next top-up (if any)
      const nextTopUp = index > 0 ? sortedFuelHistory[index - 1] : null;
      const nextTopUpDate = nextTopUp?.timestamp || null;
      
      const cycleSales = sortedSalesHistory.filter(sale => {
        const saleTime = new Date(sale.date).getTime();
        const cycleStartTime = new Date(cycleStartDate).getTime();
        if (nextTopUpDate) {
          const nextTopUpTime = new Date(nextTopUpDate).getTime();
          return saleTime >= cycleStartTime && saleTime < nextTopUpTime;
        } else {
          return saleTime >= cycleStartTime;
        }
      });
      
      const cycleLitresSold = cycleSales.reduce((sum, sale) => sum + (sale.litresSold || 0), 0);
      const cycleCustomersServed = cycleSales.length;
      
      // Calculate cycle duration
      let cycleDuration = 'N/A';
      let cycleDurationDays = 0;
      if (nextTopUpDate) {
        const diffTime = new Date(nextTopUpDate).getTime() - new Date(cycleStartDate).getTime();
        cycleDurationDays = diffTime / (1000 * 60 * 60 * 24);
        cycleDuration = cycleDurationDays < 1 ? 'Today' : `${Math.floor(cycleDurationDays)}d`;
      } else {
        const diffTime = new Date().getTime() - new Date(cycleStartDate).getTime();
        cycleDurationDays = diffTime / (1000 * 60 * 60 * 24);
        cycleDuration = cycleDurationDays < 1 ? 'Today' : `${Math.floor(cycleDurationDays)}d`;
      }
      
      // Calculate cycle end fuel (remaining after sales)
      const cycleEndFuel = cycleStartLitres - cycleLitresSold;
      
      // Determine if cycle is complete (if there's a next top-up, it's complete)
      const isComplete = nextTopUp !== null;
      
      tripCycles.push({
        cycleNumber: sortedFuelHistory.length - index,
        startDate: cycleStartDate,
        startLitres: cycleStartLitres,
        sold: cycleLitresSold,
        remaining: cycleEndFuel,
        duration: cycleDuration,
        durationDays: cycleDurationDays,
        customersServed: cycleCustomersServed,
        isComplete: isComplete,
        adminName: topUp.adminName || 'Admin',
        note: topUp.note || '',
        fuelType: topUp.fuelType || primaryFuelType
      });
    });
    
    // Get the current active cycle
    const activeCycle = tripCycles.find(cycle => !cycle.isComplete) || (tripCycles.length > 0 ? tripCycles[0] : null);
    
    // ✅ Build complete fuel movement history
    const combinedHistory = [];
    
    // Add fuelHistory entries (depot top-ups)
    sortedFuelHistory.forEach(entry => {
      combinedHistory.push({
        date: entry.timestamp,
        activity: 'Depot Top-Up',
        fuelType: entry.fuelType || primaryFuelType,
        litres: entry.amount || 0,
        balanceAfter: 0,
        adminName: entry.adminName || 'Admin',
        note: entry.note || '',
        source: entry.source || 'main-tank',
        mainTankBefore: entry.mainTankBefore || 0,
        mainTankAfter: entry.mainTankAfter || 0
      });
    });
    
    // Add salesHistory entries (customer sales)
    sortedSalesHistory.forEach(sale => {
      combinedHistory.push({
        date: sale.date,
        activity: 'Customer Sale',
        fuelType: sale.fuelType || primaryFuelType,
        litres: sale.litresSold || 0,
        balanceAfter: 0,
        amount: sale.totalAmount || 0,
        customerName: sale.customerName || 'Unknown Customer'
      });
    });
    
    // Sort by date (newest first)
    combinedHistory.sort((a, b) => {
      const dateA = new Date(a.date);
      const dateB = new Date(b.date);
      return dateB - dateA;
    });
    
    // Calculate running balance from oldest to newest
    const sortedOldestToNewest = [...combinedHistory].sort((a, b) => {
      const dateA = new Date(a.date);
      const dateB = new Date(b.date);
      return dateA - dateB;
    });
    
    let balance = 0;
    sortedOldestToNewest.forEach(entry => {
      if (entry.activity === 'Depot Top-Up') {
        balance += entry.litres;
      } else if (entry.activity === 'Customer Sale') {
        balance -= entry.litres;
      }
      entry.balanceAfter = Math.round(balance * 100) / 100;
    });
    
    // Map back to original order
    const historyWithBalance = combinedHistory.map(entry => {
      const found = sortedOldestToNewest.find(e => 
        e.date === entry.date && 
        e.activity === entry.activity && 
        e.litres === entry.litres
      );
      return {
        ...entry,
        balanceAfter: found?.balanceAfter || 0
      };
    });
    
    return {
      totalRemaining: currentFuelRemaining,
      primaryFuelType,
      totalDepotTopUps,
      totalDepotLitresAdded,
      totalLitresSoldToCustomers,
      soldSinceLastTopUp,
      daysSinceTopUp,
      daysSinceTopUpNumber,
      avgSoldPerDay,
      customersServedSinceTopUp,
      lastDepotTopUp,
      lastDepotTopUpDate,
      lastDepotTopUpLitres,
      lastDepotTopUpFuelType, // ✅ FIX: This now correctly uses the fuel type from the top-up
      lastDepotTopUpAdmin,
      lastDepotTopUpNote,
      lastDepotTopUpSource,
      mainTankBefore,
      mainTankAfter,
      lastCustomerSale,
      lastSaleDate,
      lastSaleLitres,
      lastSaleFuelType,
      lastSaleAmount,
      tankCapacity,
      remainingPercent,
      fuelNeeded,
      refillStatus,
      refillStatusColor,
      status,
      isOnline,
      salesHistory: sortedSalesHistory,
      fuelHistory: sortedFuelHistory,
      salesSinceLastTopUp,
      tripCycles,
      activeCycle,
      combinedHistory: historyWithBalance
    };
  };

  const sections = [
    { id: 'revenue', label: ' Revenue Report' },
    { id: 'daily', label: ' Daily Activity' },
    { id: 'import', label: ' Import Fuel' },
    { id: 'stock', label: ' Company Stock' },
    { id: 'drivers', label: ' Drivers' }
  ];

  const renderContent = () => {
    switch(activeSection) {
      case 'revenue':
        return renderRevenueContent();
      case 'daily':
        return renderDailyActivityContent();
      case 'import':
        return renderImportFuelContent();
      case 'stock':
        return renderCompanyStockContent();
      case 'drivers':
        return renderDriversContent();
      default:
        return renderRevenueContent();
    }
  };

  const renderRevenueContent = () => (
    <div className="space-y-6">
      <div
        className="rounded-xl shadow-lg p-6 border border-purple-200 hover:bg-purple-600 transition-all duration-300"
        style={{ backgroundColor: '#780606' }}
      >
        <p className="text-sm font-semibold uppercase tracking-wider text-purple-100">Total Revenue</p>
        <p className="text-3xl font-bold text-white mt-1">KES {totalStats.revenue.toLocaleString()}</p>
        <div className="flex justify-between text-sm text-purple-100 mt-2">
          <span>{totalStats.litres.toLocaleString()}L Total Litres</span>
          <span>{totalStats.orders} Total Orders</span>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
        <div className="rounded-xl shadow-lg p-6 border border-orange-200 bg-orange-500 hover:bg-orange-600 transition-all duration-300">
          <p className="text-sm font-semibold uppercase tracking-wider text-orange-100"> Today</p>
          <p className="text-2xl font-bold text-white mt-1">KES {todayStats.revenue.toLocaleString()}</p>
          <div className="flex justify-between text-sm text-orange-100 mt-2">
            <span>{todayStats.litres.toLocaleString()}L</span>
            <span>{todayStats.orders} orders</span>
          </div>
        </div>

        <div className="rounded-xl shadow-lg p-6 border border-emerald-200 bg-emerald-500 hover:bg-emerald-600 transition-all duration-300">
          <p className="text-sm font-semibold uppercase tracking-wider text-emerald-100"> Weekly</p>
          <p className="text-2xl font-bold text-white mt-1">KES {weeklyStats.revenue.toLocaleString()}</p>
          <div className="flex justify-between text-sm text-emerald-100 mt-2">
            <span>{weeklyStats.litres.toLocaleString()}L</span>
            <span>{weeklyStats.orders} orders</span>
          </div>
          <div className="text-xs text-emerald-100 mt-2 opacity-75">
            {weeklyStats.startDate} - {weeklyStats.endDate}
          </div>
        </div>

        <div className="rounded-xl shadow-lg p-6 border border-sky-200 bg-blue-600 hover:bg-blue-800 transition-all duration-300">
          <p className="text-sm font-semibold uppercase tracking-wider text-sky-100"> Monthly</p>
          <p className="text-2xl font-bold text-white mt-1">KES {monthlyStats.revenue.toLocaleString()}</p>
          <div className="flex justify-between text-sm text-sky-100 mt-2">
            <span>{monthlyStats.litres.toLocaleString()}L</span>
            <span>{monthlyStats.orders} orders</span>
          </div>
          <div className="text-xs text-sky-100 mt-2 opacity-75">
            {monthlyStats.startDate} - {monthlyStats.endDate}
          </div>
        </div>

        <div className="rounded-xl shadow-lg p-6 border border-violet-200 bg-violet-500 hover:bg-violet-600 transition-all duration-300">
          <p className="text-sm font-semibold uppercase tracking-wider text-violet-100"> Yearly</p>
          <p className="text-2xl font-bold text-white mt-1">KES {yearlyStats.revenue.toLocaleString()}</p>
          <div className="flex justify-between text-sm text-violet-100 mt-2">
            <span>{yearlyStats.litres.toLocaleString()}L</span>
            <span>{yearlyStats.orders} orders</span>
          </div>
          <div className="text-xs text-violet-100 mt-2 opacity-75">
            {yearlyStats.startDate} - {yearlyStats.endDate}
          </div>
        </div>
      </div>

      <div className="rounded-xl shadow-sm border border-gray-200 bg-white">
        <div className="p-6 border-b border-gray-200">
          <h2 className="text-lg font-semibold text-gray-900"> Custom Date Range Report</h2>
          <p className="text-sm mt-1 text-gray-500">Select a specific date range to view detailed transactions</p>
        </div>

        <div className="p-6 bg-cyan-500">
          <div className="flex flex-wrap items-end gap-4">
            <div>
              <label className="block text-xs font-medium text-gray-900 mb-1">Date From</label>
              <input
                type="date"
                value={dateFrom}
                onChange={(e) => setDateFrom(e.target.value)}
                className="px-4 py-2 border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 text-red-900 bg-white border-gray-300"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-900 mb-1">Date To</label>
              <input
                type="date"
                value={dateTo}
                onChange={(e) => setDateTo(e.target.value)}
                className="px-4 py-2 border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 text-red-900 bg-white border-gray-300"
              />
            </div>
            <button
              onClick={filterSalesByDate}
              disabled={isFiltering || (!dateFrom && !dateTo)}
              className={`px-6 py-2 text-sm font-medium text-white rounded-lg transition ${isFiltering || (!dateFrom && !dateTo) ? 'bg-gray-400 cursor-not-allowed' : 'bg-blue-600 hover:bg-blue-700'}`}
            >
              {isFiltering ? 'Filtering...' : 'Show Report'}
            </button>
            {showFilteredReport && (
              <button
                onClick={resetDateFilter}
                className="px-6 py-2 text-sm font-medium rounded-lg transition text-gray-700 bg-gray-200 hover:bg-gray-300"
              >
                Clear
              </button>
            )}
          </div>
        </div>
      </div>

      {showFilteredReport && (
        <div className="rounded-xl shadow-sm border border-gray-200 bg-white">
          <div className="p-6 border-b border-gray-200">
            <div className="flex items-center justify-between flex-wrap gap-2">
              <h3 className="font-semibold text-gray-900">
                Filtered Results
                <span className="text-sm font-normal ml-2 text-gray-500">
                  ({filteredSales.length} transactions)
                </span>
              </h3>
              {filteredSales.length > 0 && (
                <div className="flex gap-4 text-sm">
                  <span className="text-gray-600">
                    Revenue: <span className="font-bold text-green-600">KES {filteredSales.reduce((sum, sale) => sum + (sale.totalAmount || 0), 0).toLocaleString()}</span>
                  </span>
                  <span className="text-gray-600">
                    Litres: <span className="font-bold text-blue-600">{filteredSales.reduce((sum, sale) => sum + (sale.litresSold || 0), 0).toLocaleString()}L</span>
                  </span>
                </div>
              )}
            </div>
          </div>

          <div className="overflow-x-auto">
            <table className="w-full">
              <thead className="bg-gray-50">
                <tr>
                  <th className="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">Date</th>
                  <th className="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">Driver</th>
                  <th className="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">Fuel</th>
                  <th className="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">Litres</th>
                  <th className="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">Amount</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-200">
                {filteredSales.length === 0 ? (
                  <tr>
                    <td colSpan="5" className="px-6 py-8 text-center text-gray-500">
                      No sales found for the selected date range
                    </td>
                  </tr>
                ) : (
                  filteredSales.map((sale, index) => (
                    <tr key={index} className="hover:bg-gray-50">
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                        {sale.date ? new Date(sale.date).toLocaleDateString() : 'N/A'}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{sale.driverName || 'N/A'}</td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{sale.fuelType || 'N/A'}</td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{sale.litresSold}L</td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                        KES {sale.totalAmount?.toLocaleString() || 0}
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );

  const renderDailyActivityContent = () => {
    const today = new Date().toISOString().split('T')[0];
    const displayDate = selectedDate || today;
    const activitiesToShow = showDailyFiltered ? filteredDailyActivities : dailyActivities;

    return (
      <div className="rounded-xl shadow-sm border border-gray-200 bg-white p-6">
        <div className="flex items-center justify-between mb-6 flex-wrap gap-4">
          <div>
            <h2 className="text-xl font-semibold text-gray-900"> Daily Activity</h2>
            <div className="flex items-center gap-2 mt-1">
              <span className="text-xs flex items-center gap-1 text-green-600">
                <span className="w-2 h-2 bg-green-500 rounded-full animate-pulse inline-block"></span>
                Live Updates
              </span>
              {dailyLastUpdate && (
                <span className="text-xs text-gray-400">
                  Updated: {dailyLastUpdate.toLocaleTimeString()}
                </span>
              )}
            </div>
          </div>
          <button
            onClick={() => setActiveSection('revenue')}
            className="px-4 py-1.5 text-sm font-medium rounded-lg transition bg-gray-200 hover:bg-gray-300 text-gray-700"
          >
            ← Back
          </button>
        </div>

        <div className="p-4 rounded-lg mb-6 bg-cyan-500">
          <div className="flex flex-wrap items-end gap-4">
            <div>
              <label className="block text-xs font-medium text-gray-900 mb-1">Date From</label>
              <input
                type="date"
                value={dailyDateFrom}
                onChange={(e) => setDailyDateFrom(e.target.value)}
                className="px-3 py-1.5 border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 text-red-900 bg-white border-gray-300"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-900 mb-1">Date To</label>
              <input
                type="date"
                value={dailyDateTo}
                onChange={(e) => setDailyDateTo(e.target.value)}
                className="px-3 py-1.5 border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 text-red-900 bg-white border-gray-300"
              />
            </div>
            <button
              onClick={() => filterDailyActivitiesByDate()}
              disabled={!dailyDateFrom && !dailyDateTo}
              className={`px-4 py-1.5 text-sm font-medium text-white rounded-lg transition ${!dailyDateFrom && !dailyDateTo ? 'bg-gray-400 cursor-not-allowed' : 'bg-blue-600 hover:bg-blue-700'}`}
            >
              Filter Range
            </button>
            {showDailyFiltered && (
              <button
                onClick={resetDailyFilter}
                className="px-4 py-1.5 text-sm font-medium rounded-lg transition text-gray-700 bg-gray-200 hover:bg-gray-300"
              >
                Clear
              </button>
            )}
          </div>
          <div className="mt-3 flex items-center gap-3">
            <span className="text-sm text-blue-700">Or select single date:</span>
            <input
              type="date"
              value={displayDate}
              onChange={handleDateChange}
              className="px-3 py-1.5 border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 text-red-900 bg-white border-gray-300"
            />
            {!showDailyFiltered && (
              <span className="text-xs text-gray-600 ml-2">
                ({activitiesToShow.length} activities)
              </span>
            )}
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
          <div className="p-4 rounded-lg bg-blue-500">
            <p className="text-sm text-gray-900">Total Revenue</p>
            <p className="text-xl font-bold text-gray-900">
              KES {activitiesToShow.reduce((sum, sale) => sum + (sale.totalAmount || 0), 0).toLocaleString()}
            </p>
          </div>
          <div className="p-4 rounded-lg bg-green-500">
            <p className="text-sm text-gray-900">Total Litres</p>
            <p className="text-xl font-bold text-gray-900">
              {activitiesToShow.reduce((sum, sale) => sum + (sale.litresSold || 0), 0).toLocaleString()}L
            </p>
          </div>
          <div className="p-4 rounded-lg bg-purple-500">
            <p className="text-sm text-gray-900">Total Orders</p>
            <p className="text-xl font-bold text-gray-900">{activitiesToShow.length}</p>
          </div>
        </div>

        {activitiesToShow.length > 0 ? (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead className="bg-gray-600">
                <tr>
                  <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-100">Driver</th>
                  <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-100">Fuel Type</th>
                  <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-100">Litres</th>
                  <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-100">Amount</th>
                  <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-100">Time</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-200">
                {activitiesToShow.map((sale, index) => (
                  <tr key={index} className="hover:bg-gray-50">
                    <td className="px-4 py-3 text-sm text-gray-900">{sale.driverName || 'N/A'}</td>
                    <td className="px-4 py-3 text-sm text-gray-900">{sale.fuelType || 'N/A'}</td>
                    <td className="px-4 py-3 text-sm text-gray-900">{sale.litresSold}L</td>
                    <td className="px-4 py-3 text-sm font-medium text-gray-900">KES {sale.totalAmount?.toLocaleString() || 0}</td>
                    <td className="px-4 py-3 text-sm text-gray-500">
                      {sale.date ? new Date(sale.date).toLocaleTimeString() : 'N/A'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <div className="p-8 text-center rounded-lg bg-gray-50">
            <p className="text-lg text-gray-500">No activities found</p>
            <p className="text-sm mt-1 text-gray-400">
              {showDailyFiltered ? 'No activities in the selected date range' : 'Select a date to view activities'}
            </p>
          </div>
        )}
      </div>
    );
  };

  const renderImportFuelContent = () => {
    const sortedImports = [...importData].sort((a, b) => {
      const dateA = a.date ? new Date(a.date) : new Date(0);
      const dateB = b.date ? new Date(b.date) : new Date(0);
      return dateB - dateA;
    });

    const getFilteredImports = () => {
      let filtered = [...sortedImports];
      if (showImportFiltered) {
        if (importDateFrom) {
          const fromDate = new Date(importDateFrom);
          fromDate.setHours(0, 0, 0, 0);
          filtered = filtered.filter(entry => {
            const entryDate = new Date(entry.date);
            return entryDate >= fromDate;
          });
        }
        if (importDateTo) {
          const toDate = new Date(importDateTo);
          toDate.setHours(23, 59, 59, 999);
          filtered = filtered.filter(entry => {
            const entryDate = new Date(entry.date);
            return entryDate <= toDate;
          });
        }
      }
      return filtered;
    };

    const importsToShow = showImportFiltered ? getFilteredImports() : sortedImports;

    const totalLitres = importsToShow.reduce((sum, item) => sum + (item.litres || item.quantity || 0), 0);
    const totalCost = importsToShow.reduce((sum, item) => sum + (item.totalCost || item.cost || 0), 0);

    return (
      <div className="rounded-xl shadow-sm border border-gray-200 bg-white p-6">
        <div className="flex items-center justify-between mb-6 flex-wrap gap-4">
          <h2 className="text-xl font-semibold text-gray-900"> Import Fuel History</h2>
          <button
            onClick={() => setActiveSection('revenue')}
            className="px-4 py-1.5 text-sm font-medium rounded-lg transition bg-gray-200 hover:bg-gray-300 text-gray-700"
          >
            ← Back
          </button>
        </div>

        <div className="p-4 rounded-lg mb-6 bg-cyan-500">
          <div className="flex flex-wrap items-end gap-4">
            <div>
              <label className="block text-xs font-medium text-gray-900 mb-1">Date From</label>
              <input
                type="date"
                value={importDateFrom}
                onChange={(e) => setImportDateFrom(e.target.value)}
                className="px-3 py-1.5 border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 text-red-900 bg-white border-gray-300"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-900 mb-1">Date To</label>
              <input
                type="date"
                value={importDateTo}
                onChange={(e) => setImportDateTo(e.target.value)}
                className="px-3 py-1.5 border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 text-red-900 bg-white border-gray-300"
              />
            </div>
            <button
              onClick={filterImportsByDate}
              disabled={!importDateFrom && !importDateTo}
              className={`px-4 py-1.5 text-sm font-medium text-white rounded-lg transition ${!importDateFrom && !importDateTo ? 'bg-gray-400 cursor-not-allowed' : 'bg-blue-600 hover:bg-blue-700'}`}
            >
              Filter
            </button>
            {showImportFiltered && (
              <button
                onClick={resetImportFilter}
                className="px-4 py-1.5 text-sm font-medium rounded-lg transition text-gray-700 bg-gray-200 hover:bg-gray-300"
              >
                Clear
              </button>
            )}
          </div>
          <div className="mt-2 text-xs text-gray-600">
            Showing {importsToShow.length} records (newest first)
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
          <div className="p-4 rounded-lg bg-blue-200 border border-blue-200">
            <p className="text-sm text-gray-600"> Total Litres Imported</p>
            <p className="text-2xl font-bold text-blue-700">{totalLitres.toLocaleString()}L</p>
          </div>
          <div className="p-4 rounded-lg bg-green-200 border border-green-200">
            <p className="text-sm text-gray-600"> Total Cost</p>
            <p className="text-2xl font-bold text-green-700">KES {totalCost.toLocaleString()}</p>
          </div>
        </div>

        {importsToShow.length > 0 ? (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead className="bg-gray-600">
                <tr>
                  <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-100">Date</th>
                  <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-100">Fuel Type</th>
                  <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-100">Quantity (L)</th>
                  <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-100">Cost (KES)</th>
                  <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-100">Supplier</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-200">
                {importsToShow.map((item, index) => {
                  const litres = item.litres || item.quantity || 0;
                  const cost = item.totalCost || item.cost || 0;
                  
                  return (
                    <tr key={index} className="hover:bg-gray-50">
                      <td className="px-4 py-3 text-sm text-gray-500">
                        {item.date ? new Date(item.date).toLocaleDateString() : 'N/A'}
                      </td>
                      <td className="px-4 py-3 text-sm text-gray-900">{item.fuelType || 'N/A'}</td>
                      <td className="px-4 py-3 text-sm font-semibold text-blue-700">{litres.toLocaleString()}L</td>
                      <td className="px-4 py-3 text-sm font-semibold text-green-700">KES {cost.toLocaleString()}</td>
                      <td className="px-4 py-3 text-sm text-gray-900">{item.supplier || 'N/A'}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        ) : (
          <div className="p-8 text-center rounded-lg bg-gray-50">
            <p className="text-lg text-gray-500">
              {showImportFiltered ? 'No imports found for the selected date range' : 'No fuel import records found'}
            </p>
            <p className="text-sm mt-1 text-gray-400">
              {showImportFiltered ? 'Try adjusting your date range' : 'Import records will appear here when fuel is imported'}
            </p>
          </div>
        )}
      </div>
    );
  };

  // ✅ ENHANCED: Company Stock with accurate depot top-up tracking and trip cycles
  const renderCompanyStockContent = () => {
    const stockItems = Object.entries(fuelStockData);
    const totalFuel = totalLitresWithDrivers;
    const driversToShow = filteredFuelBreakdown;
    
    // Calculate business summary metrics
    const totalDrivers = driversData.length;
    const totalFuelWithDrivers = totalFuel;
    const totalFuelSold = salesData.reduce((sum, sale) => sum + (sale.litresSold || 0), 0);
    const totalFuelEverIssued = totalFuelSold + totalFuelWithDrivers;
    
    // Calculate fuel required for complete refill
    let totalFuelRequired = 0;
    driversData.forEach(driver => {
      const remaining = driver.remainingFuel || {};
      const totalRemaining = Object.values(remaining).reduce((sum, val) => sum + (val || 0), 0);
      const tankCapacity = driver.tankCapacity || 200;
      totalFuelRequired += Math.max(0, tankCapacity - totalRemaining);
    });

    return (
      <div className="rounded-xl shadow-sm border border-gray-200 bg-white p-6">
        <div className="flex items-center justify-between mb-6 flex-wrap gap-4">
          <div>
            <h2 className="text-xl font-semibold text-gray-900"> Company Fuel Stock</h2>
            <div className="flex items-center gap-2 mt-1">
              <span className="text-xs flex items-center gap-1 text-green-600">
                <span className="w-2 h-2 bg-green-500 rounded-full animate-pulse inline-block"></span>
                Live Updates
              </span>
              {lastUpdateTime && (
                <span className="text-xs text-gray-400">
                  Updated: {lastUpdateTime.toLocaleTimeString()}
                </span>
              )}
            </div>
          </div>
          <button
            onClick={() => setActiveSection('revenue')}
            className="px-4 py-1.5 text-sm font-medium rounded-lg transition bg-gray-200 hover:bg-gray-300 text-gray-700"
          >
            ← Back
          </button>
        </div>

        {/* Business Summary Card */}
        <div className="rounded-2xl bg-gradient-to-r from-blue-600 via-blue-700 to-indigo-800 p-6 mb-6 shadow-xl">
          <div className="text-white">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-bold flex items-center gap-2">
                <span className="text-2xl"></span> COMPANY DRIVER FUEL SUMMARY
              </h3>
              <span className="text-xs bg-white/20 px-3 py-1 rounded-full">
                {new Date().toLocaleDateString()} {new Date().toLocaleTimeString()}
              </span>
            </div>
            <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4">
              <div className="bg-white/10 rounded-xl p-3 backdrop-blur-sm">
                <p className="text-xs text-blue-200"> Drivers</p>
                <p className="text-2xl font-bold">{totalDrivers}</p>
              </div>
              <div className="bg-white/10 rounded-xl p-3 backdrop-blur-sm">
                <p className="text-xs text-blue-200"> Fuel With Drivers</p>
                <p className="text-2xl font-bold">{totalFuelWithDrivers.toLocaleString()}L</p>
              </div>
              <div className="bg-white/10 rounded-xl p-3 backdrop-blur-sm">
                <p className="text-xs text-blue-200"> Fuel Sold</p>
                <p className="text-2xl font-bold">{totalFuelSold.toLocaleString()}L</p>
              </div>
              <div className="bg-white/10 rounded-xl p-3 backdrop-blur-sm">
                <p className="text-xs text-blue-200"> Total Issued</p>
                <p className="text-2xl font-bold">{totalFuelEverIssued.toLocaleString()}L</p>
              </div>
              <div className="bg-white/10 rounded-xl p-3 backdrop-blur-sm">
                <p className="text-xs text-blue-200"> Refill Needed</p>
                <p className="text-2xl font-bold">{totalFuelRequired.toLocaleString()}L</p>
              </div>
              <div className="bg-white/10 rounded-xl p-3 backdrop-blur-sm">
                <p className="text-xs text-blue-200"> Last Updated</p>
                <p className="text-sm font-semibold">
                  {new Date().toLocaleDateString()}
                  <span className="text-xs block opacity-75">{new Date().toLocaleTimeString()}</span>
                </p>
              </div>
            </div>
          </div>
        </div>

        {/* Total fuel with all drivers combined */}
        <div className="p-4 rounded-xl mb-6 bg-gradient-to-r from-blue-500 to-blue-600 shadow-md">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-blue-100"> Total Fuel with All Drivers</p>
              <p className="text-3xl font-bold text-white">{totalFuel.toLocaleString()}L</p>
              <p className="text-xs text-blue-200 mt-1">
                Combined total across {driversData.length} drivers
              </p>
            </div>
            <div className="text-right">
              <span className="text-4xl opacity-50"></span>
            </div>
          </div>
        </div>

        {/* Per fuel type breakdown */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
          {stockItems.length > 0 ? (
            stockItems.map(([fuelType, quantity]) => {
              const percentage = totalFuel > 0 ? Math.round((quantity / totalFuel) * 100) : 0;
              const colors = {
                'Petrol': 'from-yellow-400 to-yellow-600',
                'Diesel': 'from-green-400 to-green-600',
                'Kerosene': 'from-orange-400 to-orange-600',
                'V-Power': 'from-purple-400 to-purple-600'
              };
              const gradient = colors[fuelType] || 'from-gray-400 to-gray-600';
              
              return (
                <div key={fuelType} className={`p-4 rounded-xl bg-gradient-to-r ${gradient} shadow-lg text-white`}>
                  <p className="text-sm font-medium opacity-90">{fuelType}</p>
                  <p className="text-2xl font-bold">{quantity.toLocaleString()}L</p>
                  <div className="w-full bg-white/20 rounded-full h-2 mt-2">
                    <div 
                      className="bg-white rounded-full h-2 transition-all duration-500" 
                      style={{ width: `${percentage}%` }}
                    />
                  </div>
                  <p className="text-xs opacity-80 mt-1">{percentage}% of total</p>
                </div>
              );
            })
          ) : (
            <div className="col-span-4 p-8 text-center rounded-lg bg-gray-50">
              <p className="text-lg text-gray-500">No fuel stock data available</p>
              <p className="text-sm mt-1 text-gray-400">
                Fuel data will appear here when drivers have remaining fuel
              </p>
            </div>
          )}
        </div>

        {/* Individual driver fuel breakdown - ✅ FIXED: Using lastDepotTopUpFuelType */}
        {driversData.length > 0 && (
          <div className="mt-6">
            <div className="flex flex-wrap items-center justify-between gap-4 mb-4">
              <h3 className="text-lg font-semibold text-gray-800 flex items-center gap-2">
                <span className="text-xl"></span> Individual Driver Fuel Breakdown
                <span className="text-sm font-normal text-gray-400 ml-2">
                  ({driversToShow.length} drivers)
                </span>
              </h3>
              <div className="flex items-center gap-3">
                <div className="relative">
                  <input
                    type="text"
                    value={fuelBreakdownSearchTerm}
                    onChange={(e) => setFuelBreakdownSearchTerm(e.target.value)}
                    placeholder=" Search driver..."
                    className="px-4 py-2.5 border rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 bg-white border-gray-300 w-64 pl-10"
                  />
                  <span className="absolute left-3 top-3 text-gray-400"></span>
                </div>
                {fuelBreakdownSearchTerm && (
                  <button
                    onClick={() => setFuelBreakdownSearchTerm('')}
                    className="px-3 py-2 text-sm font-medium rounded-xl transition text-gray-600 bg-gray-100 hover:bg-gray-200"
                  >
                    ✕ Clear
                  </button>
                )}
              </div>
            </div>

            {driversToShow.length > 0 ? (
              <div className="overflow-x-auto rounded-xl border border-gray-200 shadow-sm">
                <table className="w-full text-sm min-w-[1800px]">
                  <thead>
                    <tr className="bg-gradient-to-r from-gray-700 to-gray-800">
                      <th className="px-4 py-3.5 text-left text-xs font-semibold uppercase tracking-wider text-gray-200 sticky left-0 bg-gray-800 z-10 min-w-[120px]">Driver</th>
                      <th className="px-4 py-3.5 text-left text-xs font-semibold uppercase tracking-wider text-gray-200 min-w-[110px]">Phone</th>
                      <th className="px-4 py-3.5 text-left text-xs font-semibold uppercase tracking-wider text-gray-200 min-w-[90px]">Fuel Type</th>
                      <th className="px-4 py-3.5 text-left text-xs font-semibold uppercase tracking-wider text-gray-200 min-w-[140px]">Last Depot Top Up</th>
                      <th className="px-4 py-3.5 text-left text-xs font-semibold uppercase tracking-wider text-gray-200 min-w-[110px]">Top Up Date</th>
                      <th className="px-4 py-3.5 text-left text-xs font-semibold uppercase tracking-wider text-gray-200 min-w-[90px]">Days Since</th>
                      <th className="px-4 py-3.5 text-left text-xs font-semibold uppercase tracking-wider text-gray-200 min-w-[100px]">Total Top Ups</th>
                      <th className="px-4 py-3.5 text-left text-xs font-semibold uppercase tracking-wider text-gray-200 min-w-[120px]">Total Litres Added</th>
                      <th className="px-4 py-3.5 text-left text-xs font-semibold uppercase tracking-wider text-gray-200 min-w-[120px]">Sold Since Top Up</th>
                      <th className="px-4 py-3.5 text-left text-xs font-semibold uppercase tracking-wider text-gray-200 min-w-[100px]">Total Sold</th>
                      <th className="px-4 py-3.5 text-left text-xs font-semibold uppercase tracking-wider text-gray-200 min-w-[110px]">Current Fuel</th>
                      <th className="px-4 py-3.5 text-left text-xs font-semibold uppercase tracking-wider text-gray-200 min-w-[110px]">Avg Sold/Day</th>
                      <th className="px-4 py-3.5 text-left text-xs font-semibold uppercase tracking-wider text-gray-200 min-w-[130px]">Fuel Needed</th>
                      <th className="px-4 py-3.5 text-left text-xs font-semibold uppercase tracking-wider text-gray-200 min-w-[100px]">Tank Capacity</th>
                      <th className="px-4 py-3.5 text-left text-xs font-semibold uppercase tracking-wider text-gray-200 min-w-[130px]">Refill Status</th>
                      <th className="px-4 py-3.5 text-left text-xs font-semibold uppercase tracking-wider text-gray-200 min-w-[100px]">Status</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-gray-100">
                    {driversToShow.map((driver, idx) => {
                      const metrics = calculateDriverMetrics(driver);
                      const remaining = driver.remainingFuel || {};
                      const totalRemaining = Object.values(remaining).reduce((sum, val) => sum + (val || 0), 0);
                      
                      const rowBg = idx % 2 === 0 ? 'bg-white hover:bg-blue-50' : 'bg-gray-50 hover:bg-blue-50';
                      
                      const statusColor = metrics.isOnline ? 'bg-green-100 text-green-800 border-green-200' : 'bg-red-100 text-red-800 border-red-200';
                      const statusDot = metrics.isOnline ? 'bg-green-500' : 'bg-red-500';
                      
                      const lastTopUpFormatted = metrics.lastDepotTopUpDate 
                        ? new Date(metrics.lastDepotTopUpDate).toLocaleDateString()
                        : 'N/A';
                      
                      const topUpAdmin = metrics.lastDepotTopUpAdmin || 'N/A';
                      const topUpNote = metrics.lastDepotTopUpNote || '';
                      
                      // ✅ FIXED: Use lastDepotTopUpFuelType instead of primaryFuelType
                      const displayFuelType = metrics.lastDepotTopUpFuelType || 'Petrol';
                      
                      return (
                        <tr 
                          key={driver.id} 
                          className={`${rowBg} cursor-pointer transition-all duration-150 hover:shadow-md`}
                          onClick={() => {
                            setSelectedDriverId(driver.id);
                            setSelectedDriverHistory(metrics.combinedHistory || []);
                            setShowDriverHistory(true);
                          }}
                        >
                          <td className="px-4 py-3.5 text-sm font-semibold text-gray-800 sticky left-0 bg-inherit z-10">
                            <div className="flex items-center gap-2">
                              <span className="w-8 h-8 rounded-full bg-blue-100 text-blue-600 flex items-center justify-center text-xs font-bold">
                                {driver.name?.charAt(0)?.toUpperCase() || '?'}
                              </span>
                              {driver.name || 'N/A'}
                            </div>
                          </td>
                          <td className="px-4 py-3.5 text-sm text-gray-600">{driver.phone || 'N/A'}</td>
                          <td className="px-4 py-3.5 text-sm">
                            {/* ✅ FIXED: Use displayFuelType from last top-up */}
                            <span className={`px-2.5 py-1 rounded-full text-xs font-medium ${
                              displayFuelType === 'Petrol' ? 'bg-yellow-100 text-yellow-700' :
                              displayFuelType === 'Diesel' ? 'bg-green-100 text-green-700' :
                              displayFuelType === 'V-Power' ? 'bg-purple-100 text-purple-700' :
                              'bg-orange-100 text-orange-700'
                            }`}>
                              {displayFuelType}
                            </span>
                          </td>
                          <td className="px-4 py-3.5 text-sm">
                            <div>
                              <span className="font-bold text-blue-600">{metrics.lastDepotTopUpLitres}L</span>
                              {topUpAdmin !== 'N/A' && (
                                <span className="text-xs text-gray-500 block">by {topUpAdmin}</span>
                              )}
                              {topUpNote && (
                                <span className="text-xs text-gray-400 block italic"> {topUpNote}</span>
                              )}
                            </div>
                          </td>
                          <td className="px-4 py-3.5 text-sm text-gray-600">{lastTopUpFormatted}</td>
                          <td className="px-4 py-3.5 text-sm">
                            <span className={`px-2 py-1 rounded-full text-xs font-medium ${
                              metrics.daysSinceTopUp === 'Today' ? 'bg-green-100 text-green-700' :
                              metrics.daysSinceTopUp !== 'N/A' ? 'bg-blue-100 text-blue-700' :
                              'bg-gray-100 text-gray-500'
                            }`}>
                              {metrics.daysSinceTopUp}
                            </span>
                          </td>
                          <td className="px-4 py-3.5 text-sm text-center font-medium text-gray-700">{metrics.totalDepotTopUps}</td>
                          <td className="px-4 py-3.5 text-sm font-medium text-blue-600">{metrics.totalDepotLitresAdded}L</td>
                          <td className="px-4 py-3.5 text-sm font-semibold text-orange-600">{metrics.soldSinceLastTopUp}L</td>
                          <td className="px-4 py-3.5 text-sm text-gray-700">{metrics.totalLitresSoldToCustomers}L</td>
                          <td className="px-4 py-3.5 text-sm">
                            <div className="flex items-center gap-2">
                              <span className="font-bold text-blue-600">{totalRemaining.toFixed(1)}L</span>
                              <div className="w-16 bg-gray-200 rounded-full h-1.5">
                                <div 
                                  className={`h-1.5 rounded-full transition-all duration-500 ${
                                    metrics.remainingPercent > 50 ? 'bg-green-500' :
                                    metrics.remainingPercent > 20 ? 'bg-yellow-500' : 'bg-red-500'
                                  }`}
                                  style={{ width: `${Math.min(metrics.remainingPercent, 100)}%` }}
                                />
                              </div>
                            </div>
                          </td>
                          <td className="px-4 py-3.5 text-sm text-gray-600">{metrics.avgSoldPerDay}L/day</td>
                          <td className="px-4 py-3.5 text-sm">
                            <span className="font-bold text-green-600 bg-green-50 px-3 py-1.5 rounded-lg border border-green-200">
                              {metrics.fuelNeeded}L
                            </span>
                          </td>
                          <td className="px-4 py-3.5 text-sm text-gray-600">{metrics.tankCapacity}L</td>
                          <td className="px-4 py-3.5 text-sm">
                            <span className={`px-3 py-1.5 rounded-lg text-xs font-medium border ${metrics.refillStatusColor}`}>
                              {metrics.refillStatus}
                            </span>
                          </td>
                          <td className="px-4 py-3.5 text-sm">
                            <span className={`px-3 py-1.5 rounded-full text-xs font-medium inline-flex items-center gap-1.5 border ${statusColor}`}>
                              <span className={`w-2 h-2 rounded-full ${statusDot} animate-pulse`}></span>
                              {metrics.isOnline ? 'Online' : 'Offline'}
                            </span>
                          </td>
                        </tr>
                      );
                    })}
                    {/* Totals row */}
                    <tr className="bg-gradient-to-r from-blue-50 to-indigo-50 font-semibold border-t-2 border-blue-200">
                      <td className="px-4 py-4 text-sm text-gray-800 sticky left-0 bg-inherit z-10">
                        <span className="text-blue-600"> TOTAL</span>
                      </td>
                      <td className="px-4 py-4 text-sm text-gray-500">-</td>
                      <td className="px-4 py-4 text-sm text-gray-500">-</td>
                      <td className="px-4 py-4 text-sm text-gray-500">-</td>
                      <td className="px-4 py-4 text-sm text-gray-500">-</td>
                      <td className="px-4 py-4 text-sm text-gray-500">-</td>
                      <td className="px-4 py-4 text-sm text-blue-600 text-center">{driversToShow.reduce((sum, d) => sum + (d.fuelHistory?.length || 0), 0)}</td>
                      <td className="px-4 py-4 text-sm font-bold text-blue-600">{driversToShow.reduce((sum, d) => {
                        const fuelHist = d.fuelHistory || [];
                        return sum + fuelHist.reduce((s, entry) => s + (entry.amount || 0), 0);
                      }, 0)}L</td>
                      <td className="px-4 py-4 text-sm text-gray-500">-</td>
                      <td className="px-4 py-4 text-sm font-bold text-blue-600">{driversToShow.reduce((sum, d) => {
                        const sales = d.salesHistory || [];
                        return sum + sales.reduce((s, sale) => s + (sale.litresSold || 0), 0);
                      }, 0)}L</td>
                      <td className="px-4 py-4 text-sm font-bold text-green-600">{totalFuel.toFixed(1)}L</td>
                      <td className="px-4 py-4 text-sm text-gray-500">-</td>
                      <td className="px-4 py-4 text-sm font-bold text-orange-600">{totalFuelRequired}L</td>
                      <td className="px-4 py-4 text-sm text-gray-500">-</td>
                      <td className="px-4 py-4 text-sm text-gray-500">-</td>
                      <td className="px-4 py-4 text-sm text-gray-500">-</td>
                    </tr>
                  </tbody>
                </table>
              </div>
            ) : (
              <div className="p-8 text-center rounded-xl bg-gray-50 border-2 border-dashed border-gray-300">
                <p className="text-lg text-gray-500">No drivers match your search</p>
                <p className="text-sm mt-1 text-gray-400">Try adjusting your search term</p>
              </div>
            )}
          </div>
        )}

        {/* Trip Cycle Summary Modal */}
        {showDriverHistory && selectedDriverId && (
          <div className="fixed inset-0 bg-black bg-opacity-60 backdrop-blur-sm flex items-center justify-center z-50 p-4">
            <div className="bg-white rounded-2xl shadow-2xl max-w-6xl w-full max-h-[85vh] overflow-hidden animate-in fade-in zoom-in-95 duration-200">
              <div className="p-6 border-b border-gray-200 flex items-center justify-between bg-gradient-to-r from-blue-50 to-indigo-50">
                <div>
                  <h3 className="text-xl font-bold text-gray-800 flex items-center gap-2">
                    <span className="text-2xl"></span> Fuel Movement History
                  </h3>
                  <p className="text-sm text-gray-500 mt-1">
                    {driversData.find(d => d.id === selectedDriverId)?.name || 'Driver'} 
                    <span className="mx-2">•</span>
                    Complete audit trail with trip cycles
                  </p>
                </div>
                <button
                  onClick={() => {
                    setShowDriverHistory(false);
                    setSelectedDriverId(null);
                    setSelectedDriverHistory([]);
                  }}
                  className="p-2.5 hover:bg-white/50 rounded-xl transition-all duration-200 hover:rotate-90"
                >
                  <svg className="w-6 h-6 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </button>
              </div>
              <div className="p-6 overflow-y-auto max-h-[60vh]">
                {selectedDriverHistory.length > 0 ? (
                  <div className="space-y-6">
                    {/* Trip Cycle Summary */}
                    <div className="bg-gradient-to-r from-indigo-50 to-blue-50 rounded-xl p-4 border border-indigo-200">
                      <h4 className="text-sm font-semibold text-indigo-700 mb-3 flex items-center gap-2">
                        <span className="text-lg"></span> Trip Cycle Summary
                      </h4>
                      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
                        <div className="bg-white rounded-lg p-3 shadow-sm">
                          <p className="text-xs text-gray-500">Total Cycles</p>
                          <p className="text-lg font-bold text-indigo-600">
                            {driversData.find(d => d.id === selectedDriverId)?.fuelHistory?.length || 0}
                          </p>
                        </div>
                        <div className="bg-white rounded-lg p-3 shadow-sm">
                          <p className="text-xs text-gray-500">Total Fuel Issued</p>
                          <p className="text-lg font-bold text-blue-600">
                            {driversData.find(d => d.id === selectedDriverId)?.fuelHistory?.reduce((sum, entry) => sum + (entry.amount || 0), 0) || 0}L
                          </p>
                        </div>
                        <div className="bg-white rounded-lg p-3 shadow-sm">
                          <p className="text-xs text-gray-500">Total Sold</p>
                          <p className="text-lg font-bold text-green-600">
                            {driversData.find(d => d.id === selectedDriverId)?.salesHistory?.reduce((sum, sale) => sum + (sale.litresSold || 0), 0) || 0}L
                          </p>
                        </div>
                        <div className="bg-white rounded-lg p-3 shadow-sm">
                          <p className="text-xs text-gray-500">Current Balance</p>
                          <p className="text-lg font-bold text-orange-600">
                            {driversData.find(d => d.id === selectedDriverId)?.remainingFuel ? 
                              Object.values(driversData.find(d => d.id === selectedDriverId).remainingFuel).reduce((sum, val) => sum + (val || 0), 0) : 0}L
                          </p>
                        </div>
                      </div>
                    </div>

                    {/* Transaction History */}
                    <div className="overflow-x-auto">
                      <table className="w-full">
                        <thead>
                          <tr className="bg-gray-100">
                            <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-600">Date & Time</th>
                            <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-600">Activity</th>
                            <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-600">Fuel Type</th>
                            <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-600">Litres</th>
                            <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-600">Balance After</th>
                            <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-600">Details</th>
                          </tr>
                        </thead>
                        <tbody className="divide-y divide-gray-100">
                          {selectedDriverHistory.map((entry, index) => {
                            const isTopUp = entry.activity === 'Depot Top-Up';
                            const isSale = entry.activity === 'Customer Sale';
                            return (
                              <tr key={index} className={`${index % 2 === 0 ? 'bg-white' : 'bg-gray-50'} hover:bg-blue-50 transition-colors`}>
                                <td className="px-4 py-3 text-sm text-gray-600 whitespace-nowrap">
                                  {entry.date ? new Date(entry.date).toLocaleString() : 'N/A'}
                                </td>
                                <td className="px-4 py-3 text-sm">
                                  <span className={`px-3 py-1.5 rounded-full text-xs font-medium inline-flex items-center gap-1.5 ${
                                    isTopUp ? 'bg-green-100 text-green-700 border border-green-200' : 
                                    isSale ? 'bg-blue-100 text-blue-700 border border-blue-200' : 
                                    'bg-gray-100 text-gray-700 border border-gray-200'
                                  }`}>
                                    {isTopUp ? ' Depot Top-Up' : isSale ? '💰 Customer Sale' : entry.activity}
                                  </span>
                                </td>
                                <td className="px-4 py-3 text-sm text-gray-700">
                                  <span className={`px-2 py-0.5 rounded text-xs font-medium ${
                                    entry.fuelType === 'Petrol' ? 'bg-yellow-100 text-yellow-700' :
                                    entry.fuelType === 'Diesel' ? 'bg-green-100 text-green-700' :
                                    entry.fuelType === 'V-Power' ? 'bg-purple-100 text-purple-700' :
                                    'bg-orange-100 text-orange-700'
                                  }`}>
                                    {entry.fuelType || 'Petrol'}
                                  </span>
                                </td>
                                <td className={`px-4 py-3 text-sm font-bold ${
                                  isTopUp ? 'text-green-600' : isSale ? 'text-red-600' : 'text-gray-600'
                                }`}>
                                  {isTopUp ? '+' : isSale ? '-' : ''}{entry.litres}L
                                </td>
                                <td className="px-4 py-3 text-sm font-bold text-blue-600">{entry.balanceAfter}L</td>
                                <td className="px-4 py-3 text-sm text-gray-500">
                                  {isTopUp && entry.adminName && (
                                    <div className="text-xs">
                                      <span className="font-medium">Admin:</span> {entry.adminName}
                                    </div>
                                  )}
                                  {isTopUp && entry.note && (
                                    <div className="text-xs text-gray-400"> {entry.note}</div>
                                  )}
                                  {isSale && entry.customerName && (
                                    <div className="text-xs">
                                      <span className="font-medium">Customer:</span> {entry.customerName}
                                    </div>
                                  )}
                                  {isTopUp && entry.mainTankBefore !== undefined && (
                                    <div className="text-xs text-gray-400">
                                      Main Tank: {entry.mainTankBefore}L → {entry.mainTankAfter}L
                                    </div>
                                  )}
                                </td>
                              </tr>
                            );
                          })}
                        </tbody>
                      </table>
                    </div>
                  </div>
                ) : (
                  <div className="p-12 text-center text-gray-500">
                    <div className="text-5xl mb-4">📭</div>
                    <p className="text-lg font-medium">No fuel movement history available</p>
                    <p className="text-sm mt-1 text-gray-400">This driver has no recorded transactions yet</p>
                  </div>
                )}
              </div>
              <div className="sticky bottom-0 z-20 px-6 py-4 border-t border-gray-200 bg-white flex justify-between items-center rounded-b-2xl shadow-[0_-2px_10px_rgba(0,0,0,0.05)]">
                <span className="text-sm font-medium text-gray-700">
                   <span className="font-bold">{selectedDriverHistory.length}</span> transactions recorded
                </span>
                <button
                  onClick={() => {
                    setShowDriverHistory(false);
                    setSelectedDriverId(null);
                    setSelectedDriverHistory([]);
                  }}
                  className="px-6 py-2.5 text-sm font-semibold text-white bg-blue-600 hover:bg-blue-700 rounded-xl transition-all duration-200 shadow-sm hover:shadow-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
                >
                  Close
                </button>
              </div>
            </div>
          </div>
        )}
      </div>
    );
  };

  const renderDriversContent = () => {
    const driversToShow = filteredDrivers;

    const getDriverStatus = (driver) => {
      if (driver.isOnline !== undefined && driver.isOnline !== null) {
        return driver.isOnline ? 'Online' : 'Offline';
      }
      if (driver.status) {
        return driver.status === 'online' ? 'Online' : 'Offline';
      }
      return 'Offline';
    };

    const onlineCount = driversToShow.filter(d => getDriverStatus(d) === 'Online').length;
    const offlineCount = driversToShow.filter(d => getDriverStatus(d) === 'Offline').length;

    return (
      <div className="rounded-xl shadow-sm border border-gray-200 bg-white p-6">
        <div className="flex items-center justify-between mb-6 flex-wrap gap-4">
          <h2 className="text-xl font-semibold text-gray-900"> Drivers List</h2>
          <div className="flex items-center gap-3">
            <span className="text-xs flex items-center gap-1 text-green-600">
              <span className="w-2 h-2 bg-green-500 rounded-full animate-pulse inline-block"></span>
              {isLiveUpdate ? 'Live' : 'Connected'}
            </span>
            <span className="text-xs text-gray-500">Updated: {lastUpdateTime.toLocaleTimeString()}</span>
            <button
              onClick={() => setActiveSection('revenue')}
              className="px-4 py-1.5 text-sm font-medium rounded-lg transition bg-gray-200 hover:bg-gray-300 text-gray-700"
            >
              ← Back
            </button>
          </div>
        </div>

        <div className="p-2 rounded-lg mb-4 text-center text-xs bg-green-50 text-green-700">
           Real-time driver status updates active - Status changes appear instantly
          {isLiveUpdate && (
            <span className="ml-2 inline-block">
              <span className="w-2 h-2 bg-green-500 rounded-full animate-pulse inline-block mr-1"></span>
              Live
            </span>
          )}
        </div>

        <div className="p-4 rounded-lg mb-6 bg-gray-50">
          <div className="flex flex-wrap items-center gap-4">
            <div className="flex-1 min-w-[200px]">
              <label className="block text-xs font-medium text-gray-700 mb-1">Search Driver</label>
              <input
                type="text"
                value={searchDriverTerm}
                onChange={(e) => handleDriverSearch(e.target.value)}
                placeholder="Search by name or phone number..."
                className="w-full px-3 py-1.5 border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 bg-white border-gray-300"
              />
            </div>
            <div className="text-sm">
              <span className="text-gray-500">
                Found: <span className="font-bold">{driversToShow.length}</span> drivers
              </span>
            </div>
            {searchDriverTerm && (
              <button
                onClick={() => {
                  setSearchDriverTerm('');
                  setFilteredDrivers(driversData);
                }}
                className="px-3 py-1.5 text-sm font-medium rounded-lg transition text-gray-700 bg-gray-200 hover:bg-gray-300"
              >
                Clear
              </button>
            )}
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
          <div className="p-4 rounded-lg bg-gray-300">
            <p className="text-sm text-gray-500">🟢 Online Drivers</p>
            <p className="text-2xl font-bold text-green-600">{onlineCount}</p>
          </div>
          <div className="p-4 rounded-lg bg-red-200">
            <p className="text-sm text-gray-500">🔴 Offline Drivers</p>
            <p className="text-2xl font-bold text-red-600">{offlineCount}</p>
          </div>
          <div className="p-4 rounded-lg bg-blue-300">
            <p className="text-sm text-gray-500">Total Drivers</p>
            <p className="text-2xl font-bold text-gray-900">{driversToShow.length}</p>
          </div>
        </div>

        {driversToShow.length > 0 ? (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead className="bg-gray-600">
                <tr>
                  <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-200">Driver Name</th>
                  <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-200">Phone</th>
                  <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-200">Vehicle</th>
                  <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-200">Total Sales</th>
                  <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-200">Status</th>
                  <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-200">Last Activity</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-200">
                {driversToShow.map((driver) => {
                  const totalSales = driver.salesHistory 
                    ? driver.salesHistory.reduce((sum, sale) => sum + (sale.totalAmount || 0), 0) 
                    : 0;
                  const status = getDriverStatus(driver);
                  const isOnline = status === 'Online';
                  
                  return (
                    <tr key={driver.id} className="hover:bg-gray-50">
                      <td className="px-4 py-3 text-sm font-medium text-gray-900">{driver.name || 'N/A'}</td>
                      <td className="px-4 py-3 text-sm text-gray-500">{driver.phone || 'N/A'}</td>
                      <td className="px-4 py-3 text-sm text-gray-500">{driver.vehicle || 'N/A'}</td>
                      <td className="px-4 py-3 text-sm font-medium text-gray-900">KES {totalSales.toLocaleString()}</td>
                      <td className="px-4 py-3 text-sm">
                        <span className={`px-2 py-1 rounded-full text-xs font-medium inline-flex items-center gap-1 ${
                          isOnline ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-800'
                        }`}>
                          <span className={`w-2 h-2 rounded-full ${isOnline ? 'bg-green-500 animate-pulse' : 'bg-red-500'}`}></span>
                          {isOnline ? 'Online' : 'Offline'}
                        </span>
                      </td>
                      <td className="px-4 py-3 text-sm text-gray-500">
                        {driver.lastUpdated ? new Date(driver.lastUpdated).toLocaleTimeString() : 'N/A'}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        ) : (
          <div className="p-8 text-center rounded-lg bg-gray-50">
            <p className="text-lg text-gray-500">
              {searchDriverTerm ? 'No drivers match your search' : 'No drivers found'}
            </p>
            <p className="text-sm mt-1 text-gray-400">
              {searchDriverTerm ? 'Try a different search term' : 'Drivers will appear here when they are added'}
            </p>
          </div>
        )}
      </div>
    );
  };

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-100">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-green-500"></div>
      </div>
    );
  }

  if (!isAuthenticated) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-100">
        <div className="max-w-md w-full bg-white rounded-xl shadow-2xl p-8">
          <div className="text-center mb-8">
            <div className="flex justify-center mb-4">
              <div className="relative w-20 h-20">
                <Image
                  src="/images/logo.png"
                  alt="Company Logo"
                  fill
                  className="object-contain"
                  priority
                />
              </div>
            </div>
            <h2 className="text-2xl font-bold text-gray-900">Secure Access Required</h2>
            <p className="text-sm mt-2 text-gray-500">Please enter the password to access the comprehensive report</p>
          </div>
          
          <form onSubmit={handlePasswordSubmit} className="space-y-4">
            <div>
              <input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="Enter password"
                className="w-full px-4 py-3 rounded-lg border border-gray-300 focus:outline-none focus:ring-2 focus:ring-blue-500 bg-white"
                autoFocus
              />
              {passwordError && (
                <p className="text-red-500 text-sm mt-2">{passwordError}</p>
              )}
            </div>
            <button
              type="submit"
              className="w-full bg-blue-600 hover:bg-blue-700 text-white font-semibold py-3 px-4 rounded-lg transition duration-200"
            >
              Unlock Report
            </button>
          </form>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen p-4 md:p-6 bg-gray-100">
      <div className="max-w-7xl mx-auto">
        <div className="space-y-6">
          {/* Header */}
          <div className="flex items-center justify-between flex-wrap gap-4">
            <div>
              <h1 className="text-2xl font-bold"> Comprehensive Report</h1>
              <p className="text-sm mt-1 text-gray-500">Weekly, Monthly, and Yearly revenue analysis</p>
            </div>
            <Link href="/reports" className="text-sm text-gray-500 hover:text-gray-700 flex items-center space-x-1">
              <span>←</span>
              <span>Back to Reports</span>
            </Link>
          </div>

          {/* Section Navigation Tabs */}
          <div className="flex flex-wrap gap-2 border-b border-gray-200 pb-2">
            {sections.map((section) => (
              <button
                key={section.id}
                onClick={() => setActiveSection(section.id)}
                className={`px-4 py-2 rounded-lg text-sm font-medium transition-all duration-200 ${
                  activeSection === section.id
                    ? 'bg-blue-600 text-white shadow-md'
                    : 'text-gray-600 hover:text-gray-900 hover:bg-gray-100'
                }`}
              >
                {section.label}
              </button>
            ))}
          </div>

          {/* Dynamic Content */}
          {renderContent()}
        </div>
      </div>
    </div>
  );
}