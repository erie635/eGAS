'use client';

import { useState, useCallback, useMemo, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { db, auth } from '../../../lib/firebase';
import { collection, addDoc, doc, getDoc, updateDoc, getDocs, runTransaction } from 'firebase/firestore';
import { getDoc as getFirestoreDoc } from 'firebase/firestore';
import toast from 'react-hot-toast';

// Tank capacity for each fuel type
const TANK_CAPACITY = {
  Petrol: 100000,
  Diesel: 100000,
  Kerosene: 100000,
  'V-Power': 100000
};

// Validation function (reusable)
const validateFuelImport = (fuelType, litres, currentStock) => {
  const capacity = TANK_CAPACITY[fuelType] || 0;
  const currentAmount = currentStock[fuelType] || 0;

  if (currentAmount > capacity) {
    throw new Error(`${fuelType} tank contains invalid value (${currentAmount.toFixed(1)}L). Maximum allowed is ${capacity}L. Please fix the stock first.`);
  }

  if (currentAmount >= capacity) {
    throw new Error(`${fuelType} tank is FULL! Current: ${currentAmount.toFixed(1)}L out of ${capacity}L. Cannot import more fuel.`);
  }

  const newAmount = currentAmount + litres;
  if (newAmount > capacity) {
    const availableSpace = capacity - currentAmount;
    throw new Error(`Cannot import ${litres}L! ${fuelType} tank capacity is ${capacity}L. Only ${availableSpace.toFixed(1)}L space available.`);
  }

  return { currentAmount, newAmount, capacity, availableSpace: capacity - currentAmount };
};

export default function ImportFuel() {
  const router = useRouter();
  const [loading, setLoading] = useState(false);
  const [userBackground, setUserBackground] = useState('white');
  const [formData, setFormData] = useState({
    supplier: '',
    fuelType: 'Petrol',
    litres: '',
    costPerLitre: '',
    date: new Date().toISOString().split('T')[0] // Auto-set to today
  });

  // Fetch user background
  useEffect(() => {
    const fetchUserBackground = async () => {
      const currentUser = auth.currentUser;
      if (!currentUser) return;

      try {
        const userDoc = await getFirestoreDoc(doc(db, 'users', currentUser.uid));
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

  // Memoized total cost calculation
  const totalCost = useMemo(() => {
    const litres = parseFloat(formData.litres) || 0;
    const cost = parseFloat(formData.costPerLitre) || 0;
    return litres * cost;
  }, [formData.litres, formData.costPerLitre]);

  // Handle form changes
  const handleChange = useCallback((e) => {
    const { name, value } = e.target;
    setFormData(prev => ({ ...prev, [name]: value }));
  }, []);

  // Main submit handler
  const handleSubmit = useCallback(async (e) => {
    e.preventDefault();
    setLoading(true);

    try {
      const parsedLitres = parseFloat(formData.litres);
      const parsedCost = parseFloat(formData.costPerLitre);

      if (parsedLitres <= 0) {
        toast.error('Please enter a valid amount of litres');
        setLoading(false);
        return;
      }

      if (parsedCost <= 0) {
        toast.error('Please enter a valid cost per litre');
        setLoading(false);
        return;
      }

      // ============================================
      // STEP 1: Use transaction for atomic updates
      // ============================================
      const companyRef = doc(db, 'company', 'fuelStock');

      const result = await runTransaction(db, async (transaction) => {
        const companySnap = await transaction.get(companyRef);

        let currentStock = { Petrol: 0, Diesel: 0, Kerosene: 0, 'V-Power': 0 };
        let existingLogs = [];

        if (companySnap.exists()) {
          const data = companySnap.data();
          currentStock = data.stock || { Petrol: 0, Diesel: 0, Kerosene: 0, 'V-Power': 0 };
          existingLogs = data.activityLog || [];
        }

        // Validate import
        const { currentAmount, newAmount, capacity } = validateFuelImport(
          formData.fuelType,
          parsedLitres,
          currentStock
        );

        // Update stock
        const updatedStock = {
          ...currentStock,
          [formData.fuelType]: newAmount
        };

        // Create activity log entry with price information
        const logEntry = {
          fuelType: formData.fuelType,
          amount: parsedLitres,
          action: 'add',
          actionType: 'Fuel Import',
          reason: `Imported ${parsedLitres}L ${formData.fuelType} from ${formData.supplier} at KES ${parsedCost.toFixed(2)}/L`,
          timestamp: new Date().toISOString(),
          date: new Date().toLocaleString(),
          previousTankAmount: currentAmount,
          newTankAmount: newAmount,
          updatedBy: 'Admin',
          supplier: formData.supplier,
          costPerLitre: parsedCost,
          totalCost: totalCost,
          importDate: formData.date,
          priceInfo: `KES ${parsedCost.toFixed(2)}/L | Total: KES ${totalCost.toFixed(2)}`,
          capacityInfo: `${newAmount}/${capacity}L (${((newAmount / capacity) * 100).toFixed(1)}%)`,
          pricePerLitre: parsedCost,
          totalCost: totalCost,
          costDisplay: `💰 KES ${parsedCost.toFixed(2)}/L | 💳 Total: KES ${totalCost.toFixed(2)}`
        };

        // Add to activity log (keep last 100)
        const updatedLogs = [logEntry, ...existingLogs].slice(0, 100);

        // Update company document
        transaction.update(companyRef, {
          stock: updatedStock,
          activityLog: updatedLogs,
          lastUpdated: new Date().toISOString()
        });

        // ============================================
        // STEP 2: Save to fuelImports (History)
        // ============================================
        const importRef = doc(collection(db, 'fuelImports'));
        transaction.set(importRef, {
          ...formData,
          litres: parsedLitres,
          costPerLitre: parsedCost,
          totalCost: totalCost,
          createdAt: new Date().toISOString()
        });

        return { newAmount, capacity, currentAmount, parsedLitres };
      });

      // ============================================
      // STEP 3: Distribute fuel to active drivers
      // ============================================
      const driversSnapshot = await getDocs(collection(db, 'drivers'));
      const activeDrivers = driversSnapshot.docs
        .map(doc => ({ id: doc.id, ...doc.data() }))
        .filter(d => d.isOnline === true || d.status === 'available');

      if (activeDrivers.length > 0) {
        const litresPerDriver = result.parsedLitres / activeDrivers.length;

        const updatePromises = activeDrivers.map(driver => {
          const docRef = doc(db, 'drivers', driver.id);
          const currentFuel = driver.remainingFuel || {};
          const fuelType = formData.fuelType;

          return updateDoc(docRef, {
            [`remainingFuel.${fuelType}`]: (currentFuel[fuelType] || 0) + litresPerDriver,
            fuelUpdatedAt: new Date().toISOString(),
            fuelHistory: [
              {
                type: 'import',
                date: new Date().toISOString(),
                fuelType: fuelType,
                litresAdded: litresPerDriver,
                supplier: formData.supplier,
                costPerLitre: parseFloat(formData.costPerLitre),
                totalCost: totalCost,
                importDate: formData.date,
                priceInfo: `KES ${parseFloat(formData.costPerLitre).toFixed(2)}/L | Total: KES ${totalCost.toFixed(2)}`
              },
              ...(driver.fuelHistory || [])
            ].slice(0, 50)
          });
        });

        await Promise.all(updatePromises);

        toast.success(`✅ ${result.parsedLitres}L of ${formData.fuelType} distributed to ${activeDrivers.length} active drivers!`, {
          duration: 4000,
          icon: '🚚'
        });
      } else {
        toast(`⚠️ Fuel added to company stock but no active drivers to distribute to.`, {
          duration: 4000,
          icon: 'ℹ️'
        });

      }

      // ============================================
      // STEP 4: Show success messages with price
      // ============================================
      const percentageFull = (result.newAmount / result.capacity) * 100;
      let statusEmoji = percentageFull > 90 ? '⚠️' : percentageFull > 80 ? '🟡' : '✅';

      toast.success(`${statusEmoji} ${result.parsedLitres}L ${formData.fuelType} imported successfully! Tank: ${result.newAmount.toFixed(1)}L (${percentageFull.toFixed(1)}% of capacity)`, {
        duration: 4000,
        icon: '⛽'
      });

      toast.success(`💰 Cost: KES ${parseFloat(formData.costPerLitre).toFixed(2)}/L | Total: KES ${totalCost.toFixed(2)}`, {
        duration: 4000,
        icon: '💳'
      });

      router.push('/fuel');

    } catch (error) {
      console.error('Error importing fuel:', error);
      toast.error(error.message || 'Failed to import fuel');
    } finally {
      setLoading(false);
    }
  }, [formData, totalCost, router]);

  return (
    <div className={`p-4 md:p-6 transition-colors duration-300 ${getBackgroundClass()}`}>
      <div className="max-w-4xl mx-auto space-y-6">
        <div className="flex items-center justify-between">
          <div>
            <h1 className={`text-2xl font-bold ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'}`}> Import Fuel</h1>
            <p className={`text-sm ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>
              Import fuel from depot to system and distribute to active drivers
            </p>
          </div>
          <Link href="/fuel" className={`text-sm ${userBackground === 'dark' ? 'text-gray-400 hover:text-gray-200' : 'text-gray-500 hover:text-gray-700'} flex items-center space-x-1`}>
            <span>←</span>
            <span>Back to Fuel</span>
          </Link>
        </div>

        <div className={`rounded-xl shadow-sm p-6 border ${userBackground === 'dark' ? 'border-gray-700' : 'border-gray-100'} ${getCardClass()}`}>
          <form onSubmit={handleSubmit} className="space-y-6 max-w-2xl">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div>
                <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-2`}>Supplier *</label>
                <input
                  type="text"
                  name="supplier"
                  required
                  className={`w-full px-4 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500 ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'}`}
                  placeholder="Supplier name"
                  value={formData.supplier}
                  onChange={handleChange}
                />
              </div>

              <div>
                <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-2`}>Fuel Type *</label>
                <select
                  name="fuelType"
                  required
                  className={`w-full px-4 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500 ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'}`}
                  value={formData.fuelType}
                  onChange={handleChange}
                >
                  <option value="Petrol">Petrol</option>
                  <option value="Diesel">Diesel</option>
                  <option value="Kerosene">Kerosene</option>
                  <option value="V-Power">V-Power</option>
                </select>
              </div>

              <div>
                <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-2`}>Litres *</label>
                <input
                  type="number"
                  name="litres"
                  required
                  className={`w-full px-4 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500 ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'}`}
                  placeholder="1000"
                  step="0.01"
                  min="0"
                  value={formData.litres}
                  onChange={handleChange}
                />
              </div>

              <div>
                <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-2`}>Cost per Litre (KES) *</label>
                <input
                  type="number"
                  name="costPerLitre"
                  required
                  className={`w-full px-4 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500 ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'}`}
                  placeholder="185"
                  step="0.01"
                  min="0"
                  value={formData.costPerLitre}
                  onChange={handleChange}
                />
              </div>

              <div>
                <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-2`}>Import Date</label>
                <div className={`w-full px-4 py-2 border rounded-lg ${userBackground === 'dark' ? 'bg-gray-700 text-gray-400 border-gray-600' : 'bg-gray-100 text-gray-700 border-gray-300'}`}>
                  {formData.date}
                </div>
                <p className={`text-xs mt-1 ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-400'}`}>Date is automatically set to today</p>
              </div>

              <div className="flex items-end">
                <div className={`p-3 rounded-lg border w-full ${userBackground === 'dark' ? 'bg-gray-700 border-gray-600' : 'bg-gray-50 border-gray-200'}`}>
                  <p className={`text-xs ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>Total Cost</p>
                  <p className="text-lg font-bold text-green-600">
                    KES {totalCost.toFixed(2)}
                  </p>
                </div>
              </div>
            </div>

            {/* Info Box */}
            <div className="p-4 rounded-lg bg-cyan-500 text-white border border-blue-700">
              <p className="text-sm">
                ℹ️ Imported fuel will be:
                <br />
                • Added to company stock with price tracking
                <br />
                • Validated against tank capacity
                <br />
                • Distributed to all active drivers
                <br />
                • Reflected in the fuel tanks instantly
                <br />
                • <strong>Price will be shown in the activity log</strong>
              </p>
            </div>

            <div className="flex justify-end space-x-3 pt-6 border-t border-gray-200">
              <Link
                href="/fuel"
                className={`px-4 py-2 text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300 bg-gray-700 hover:bg-gray-600' : 'text-gray-700 bg-gray-100 hover:bg-gray-200'} rounded-lg transition`}
              >
                Cancel
              </Link>
              <button
                type="submit"
                disabled={loading}
                className="px-6 py-2 text-sm font-medium text-white bg-green-500 rounded-lg hover:bg-green-600 transition disabled:opacity-50 disabled:cursor-not-allowed"
              >
                {loading ? (
                  <span className="flex items-center space-x-2">
                    <svg className="animate-spin h-4 w-4 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                      <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                      <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                    </svg>
                    <span>Importing...</span>
                  </span>
                ) : (
                  'Import Fuel'
                )}
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
  );
}