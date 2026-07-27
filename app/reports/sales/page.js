'use client';

import { useState, useEffect } from 'react';
import { db, auth } from '../../../lib/firebase';
import { collection, getDocs, doc, getDoc } from 'firebase/firestore';
import toast from 'react-hot-toast';
import Link from 'next/link';

export default function SalesReport() {
  const [salesData, setSalesData] = useState([]);
  const [loading, setLoading] = useState(true);
  const [totalStats, setTotalStats] = useState({
    totalRevenue: 0,
    totalLitres: 0,
    totalOrders: 0
  });
  const [userBackground, setUserBackground] = useState('white');

  // States for pagination and filtering
  const [showAllSales, setShowAllSales] = useState(false);
  const [filteredSales, setFilteredSales] = useState([]);
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');
  const [isFiltering, setIsFiltering] = useState(false);

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

  useEffect(() => {
    fetchSalesData();
  }, []);

  async function fetchSalesData() {
    setLoading(true);
    try {
      const driversSnapshot = await getDocs(collection(db, 'drivers'));
      const allSales = [];

      driversSnapshot.docs.forEach(doc => {
        const data = doc.data();
        if (data.salesHistory) {
          data.salesHistory.forEach(sale => {
            allSales.push({
              ...sale,
              driverId: doc.id,
              driverName: data.name
            });
          });
        }
      });

      const sortedSales = allSales.sort((a, b) =>
        new Date(b.date) - new Date(a.date)
      ).slice(0, 100);

      const totalRevenue = sortedSales.reduce((sum, sale) => sum + (sale.totalAmount || 0), 0);
      const totalLitres = sortedSales.reduce((sum, sale) => sum + (sale.litresSold || 0), 0);

      setTotalStats({
        totalRevenue,
        totalLitres,
        totalOrders: sortedSales.length
      });

      setSalesData(sortedSales);
      setFilteredSales(sortedSales);
    } catch (error) {
      console.error('Error fetching sales data:', error);
      toast.error('Failed to load sales data');
    } finally {
      setLoading(false);
    }
  }

  // Filter sales by date
  const filterSalesByDate = () => {
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

  // Reset date filter
  const resetDateFilter = () => {
    setDateFrom('');
    setDateTo('');
    setFilteredSales(salesData);
    toast('Date filter cleared');
  };

  // Toggle show all sales
  const toggleShowAllSales = () => {
    setShowAllSales(!showAllSales);
    if (!showAllSales) {
      filterSalesByDate();
    }
  };

  // Get display sales based on view mode
  const getDisplaySales = () => {
    const sales = showAllSales ? filteredSales : salesData;
    return showAllSales ? sales : sales.slice(0, 10);
  };

  // Get display sales
  const displaySales = getDisplaySales();
  const hasMoreSales = salesData.length > 10;

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

  if (loading) {
    return (
      <div className={`min-h-screen flex items-center justify-center ${getBackgroundClass()}`}>
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-green-500"></div>
      </div>
    );
  }

  return (
    <div className={`min-h-screen p-4 md:p-6 transition-colors duration-300 ${getBackgroundClass()}`}>
      <div className="max-w-7xl mx-auto">
        <div className="space-y-6">
          <div className="flex items-center justify-between">
            <div>
              <h1 className="text-2xl font-bold">Sales Report</h1>
              <p className={`text-sm mt-1 ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>
                View all sales transactions
              </p>
            </div>
            <Link href="/reports" className={`text-sm ${userBackground === 'dark' ? 'text-gray-400 hover:text-gray-200' : 'text-gray-500 hover:text-gray-700'} flex items-center space-x-1`}>
              <span>←</span>
              <span>Back to Reports</span>
            </Link>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            <div className={`rounded-xl shadow-lg p-6 border ${userBackground === 'dark' ? 'border-emerald-800' : 'border-emerald-200'} ${getCardClass()} bg-emerald-500 dark:bg-emerald-900 hover:bg-emerald-600 dark:hover:bg-emerald-800 transition-all duration-300`}>
              <p className="text-sm font-semibold uppercase tracking-wider text-emerald-100 dark:text-emerald-300"> Total Revenue</p>
              <p className="text-3xl font-bold text-white dark:text-emerald-100 mt-1">KES {totalStats.totalRevenue.toLocaleString()}</p>
            </div>

            <div className={`rounded-xl shadow-lg p-6 border ${userBackground === 'dark' ? 'border-sky-800' : 'border-sky-200'} ${getCardClass()} bg-sky-500 dark:bg-sky-900 hover:bg-sky-600 dark:hover:bg-sky-800 transition-all duration-300`}>
              <p className="text-sm font-semibold uppercase tracking-wider text-sky-100 dark:text-sky-300"> Total Litres Sold</p>
              <p className="text-3xl font-bold text-white dark:text-sky-100 mt-1">{totalStats.totalLitres.toLocaleString()}L</p>
            </div>

            <div className={`rounded-xl shadow-lg p-6 border ${userBackground === 'dark' ? 'border-violet-800' : 'border-violet-200'} ${getCardClass()} bg-violet-500 dark:bg-violet-900 hover:bg-violet-600 dark:hover:bg-violet-800 transition-all duration-300`}>
              <p className="text-sm font-semibold uppercase tracking-wider text-violet-100 dark:text-violet-300"> Total Orders</p>
              <p className="text-3xl font-bold text-white dark:text-violet-100 mt-1">{totalStats.totalOrders}</p>
            </div>
          </div>

          <div className={`rounded-xl shadow-sm border ${userBackground === 'dark' ? 'border-gray-700' : 'border-gray-200'} ${getCardClass()}`}>
            <div className={`p-6 border-b ${userBackground === 'dark' ? 'border-gray-700' : 'border-gray-200'}`}>
              <div className="flex items-center justify-between">
                <h2 className={`text-lg font-semibold ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'}`}>
                  Sales History
                  <span className={`text-sm font-normal ml-2 ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>
                    ({showAllSales ? filteredSales.length : Math.min(10, salesData.length)} of {salesData.length} transactions)
                  </span>
                </h2>
                {hasMoreSales && (
                  <button
                    onClick={toggleShowAllSales}
                    className="text-sm text-blue-600 hover:text-blue-800 font-medium transition"
                  >
                    {showAllSales ? 'Show Less' : 'See All Transactions'}
                  </button>
                )}
              </div>
            </div>

            {/* Date Filter */}
            {showAllSales && (
              <div className={`p-4 border-b ${userBackground === 'dark' ? 'border-gray-700 bg-gray-800/50' : 'border-gray-200 bg-gray-50'}`}>
                <div className="flex flex-wrap items-end gap-3">
                  <div>
                    <label className={`block text-xs font-medium ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-700'} mb-1`}>Date From</label>
                    <input
                      type="date"
                      value={dateFrom}
                      onChange={(e) => setDateFrom(e.target.value)}
                      className={`px-3 py-1.5 border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'}`}
                    />
                  </div>
                  <div>
                    <label className={`block text-xs font-medium ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-700'} mb-1`}>Date To</label>
                    <input
                      type="date"
                      value={dateTo}
                      onChange={(e) => setDateTo(e.target.value)}
                      className={`px-3 py-1.5 border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'}`}
                    />
                  </div>
                  <button
                    onClick={filterSalesByDate}
                    disabled={isFiltering || (!dateFrom && !dateTo)}
                    className={`px-4 py-1.5 text-sm font-medium text-white rounded-lg transition ${isFiltering || (!dateFrom && !dateTo)
                        ? 'bg-gray-400 cursor-not-allowed'
                        : 'bg-blue-500 hover:bg-blue-600'
                      }`}
                  >
                    {isFiltering ? 'Filtering...' : 'Filter'}
                  </button>
                  {(dateFrom || dateTo) && (
                    <button
                      onClick={resetDateFilter}
                      className={`px-4 py-1.5 text-sm font-medium rounded-lg transition ${userBackground === 'dark' ? 'text-gray-300 bg-gray-700 hover:bg-gray-600' : 'text-gray-700 bg-gray-200 hover:bg-gray-300'}`}
                    >
                      Clear
                    </button>
                  )}
                </div>
              </div>
            )}

            <div className="overflow-x-auto">
              <table className="w-full">
                <thead className={userBackground === 'dark' ? 'bg-gray-800' : 'bg-gray-600'}>
                  <tr>
                    <th className={`px-6 py-3 text-left text-xs font-medium uppercase tracking-wider ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-200'}`}>Date</th>
                    <th className={`px-6 py-3 text-left text-xs font-medium uppercase tracking-wider ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-200'}`}>Driver</th>
                    <th className={`px-6 py-3 text-left text-xs font-medium uppercase tracking-wider ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-200'}`}>Fuel</th>
                    <th className={`px-6 py-3 text-left text-xs font-medium uppercase tracking-wider ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-200'}`}>Litres</th>
                    <th className={`px-6 py-3 text-left text-xs font-medium uppercase tracking-wider ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-200'}`}>Amount</th>
                  </tr>
                </thead>
                <tbody className={`divide-y ${userBackground === 'dark' ? 'divide-gray-700' : 'divide-gray-200'}`}>
                  {displaySales.length === 0 ? (
                    <tr>
                      <td colSpan="5" className={`px-6 py-8 text-center ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>
                        {showAllSales && (dateFrom || dateTo)
                          ? 'No sales found for the selected date range'
                          : 'No sales data found'}
                      </td>
                    </tr>
                  ) : (
                    displaySales.map((sale, index) => (
                      <tr key={index} className={userBackground === 'dark' ? 'hover:bg-gray-800/50' : 'hover:bg-gray-50'}>
                        <td className={`px-6 py-4 whitespace-nowrap text-sm ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>
                          {sale.date ? new Date(sale.date).toLocaleDateString() : 'N/A'}
                        </td>
                        <td className={`px-6 py-4 whitespace-nowrap text-sm ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'}`}>{sale.driverName || 'N/A'}</td>
                        <td className={`px-6 py-4 whitespace-nowrap text-sm ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'}`}>{sale.fuelType || 'N/A'}</td>
                        <td className={`px-6 py-4 whitespace-nowrap text-sm ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'}`}>{sale.litresSold}L</td>
                        <td className={`px-6 py-4 whitespace-nowrap text-sm font-medium ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'}`}>
                          KES {sale.totalAmount?.toLocaleString() || 0}
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
    </div>
  );
}