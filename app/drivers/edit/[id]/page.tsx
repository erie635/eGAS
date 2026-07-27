'use client';

import { useState, useEffect, useRef, useCallback, useMemo } from 'react';
import { useRouter, useParams } from 'next/navigation';
import Link from 'next/link';
import { db, auth, storage } from '../../../../lib/firebase';
import { doc, getDoc, updateDoc, collection, query, where, getDocs, setDoc, deleteDoc, onSnapshot, runTransaction } from 'firebase/firestore';
import { ref, uploadBytesResumable, getDownloadURL, deleteObject } from 'firebase/storage';
import { createUserWithEmailAndPassword, updatePassword, signInWithEmailAndPassword, getAuth, updateProfile, deleteUser, sendPasswordResetEmail } from 'firebase/auth';
import toast from 'react-hot-toast';

interface DriverData {
  id: string;
  userId?: string;
  name: string;
  email: string;
  phone: string;
  license: string;
  vehicleType: string;
  numberPlate: string;
  isOnline: boolean;
  isAvailable: boolean;
  status: string;
  userType: string;
  photoURL?: string;
  driverPhoto?: string;
  remainingFuel?: {
    Petrol: number;
    Diesel: number;
    Kerosene: number;
    'V-Power': number;
  };
  completedOrders?: number;
  totalRevenueToday?: number;
  createdAt?: string;
  updatedAt?: string;
  hasPasswordSet?: boolean;
  authUserId?: string;
  latitude?: number;
  longitude?: number;
  speed?: number;
  heading?: number;
  lastUpdate?: string;
  isApproved?: boolean;
  profileComplete?: boolean;
  rating?: number;
  driverSince?: string;
  pricePerKm?: number;
  orderAccepted?: boolean;
  activeOrderId?: string | null;
  orderStartedAt?: string | null;
  currentClientName?: string | null;
  currentClientPhone?: string | null;
  currentClientLocation?: string | null;
  currentClientPhoto?: string | null;
  fuelUpdatedAt?: string;
  fuelHistory?: any[];
  salesHistory?: any[];
  totalFuelSoldToday?: number;
  lastSaleDate?: string | null;
  lastSaleFuelType?: string | null;
  lastSaleLitres?: number;
  lastSaleAmount?: number;
  lastSaleTime?: string | null;
  lastOrderTime?: string | null;
  lastCompletedOrderAt?: string | null;
  onlineHistory?: any[];
  offlineHistory?: any[];
  lastOnlineTime?: string | null;
  lastOfflineTime?: string | null;
}

export default function EditDriver() {
  const router = useRouter();
  const params = useParams();
  const driverId = params?.id as string;
  const fileInputRef = useRef<HTMLInputElement>(null);
  const statusContainerRef = useRef<HTMLDivElement>(null);
  const hoverTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const isMountedRef = useRef(true);
  const unsubscribeRef = useRef<(() => void) | null>(null);
  const emailCheckCache = useRef<Map<string, boolean>>(new Map());
  const toastShownRef = useRef(false);
  const fuelToastShownRef = useRef(false);

  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [uploadingPhoto, setUploadingPhoto] = useState(false);
  const [driver, setDriver] = useState<DriverData | null>(null);
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [photoPreview, setPhotoPreview] = useState<string | null>(null);
  const [isPhotoLoading, setIsPhotoLoading] = useState(false);
  const [showPasswordModal, setShowPasswordModal] = useState(false);
  const [showFuelModal, setShowFuelModal] = useState(false);
  const [showDeleteModal, setShowDeleteModal] = useState(false);
  const [passwordData, setPasswordData] = useState({ newPassword: '', confirmPassword: '' });
  const [fuelData, setFuelData] = useState({ fuelType: 'Petrol', amount: 0, note: '' });
  const [updatingPassword, setUpdatingPassword] = useState(false);
  const [updatingFuel, setUpdatingFuel] = useState(false);
  const [deletingDriver, setDeletingDriver] = useState(false);
  const [uploadProgress, setUploadProgress] = useState(0);
  const [hasExistingPassword, setHasExistingPassword] = useState(false);
  const [emailError, setEmailError] = useState(false);
  const [updatingStatus, setUpdatingStatus] = useState(false);
  const [showStatusUpdates, setShowStatusUpdates] = useState(false);
  const [statusUpdateMessages, setStatusUpdateMessages] = useState<string[]>([]);
  const [hasReceivedUpdate, setHasReceivedUpdate] = useState(false);
  const [mainTankStock, setMainTankStock] = useState<{ [key: string]: number }>({
    Petrol: 0,
    Diesel: 0,
    Kerosene: 0,
    'V-Power': 0
  });
  const [userBackground, setUserBackground] = useState('white');
  const [formData, setFormData] = useState({
    name: '',
    email: '',
    phone: '',
    license: '',
    vehicleType: '',
    numberPlate: '',
    isOnline: false,
    isAvailable: false,
    status: 'offline',
    isApproved: true,
    pricePerKm: 0,
    userType: 'driver'
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

  // Fetch main tank stock
  const fetchMainTankStock = useCallback(async () => {
    try {
      const companyRef = doc(db, 'company', 'fuelStock');
      const companySnap = await getDoc(companyRef);
      if (companySnap.exists()) {
        const data = companySnap.data();
        setMainTankStock(data.stock || { Petrol: 0, Diesel: 0, Kerosene: 0, 'V-Power': 0 });
      }
    } catch (error) {
      console.error('Error fetching main tank stock:', error);
    }
  }, []);

  useEffect(() => {
    isMountedRef.current = true;
    if (driverId) {
      fetchDriver();
      fetchMainTankStock();
    }
    return () => {
      isMountedRef.current = false;
      if (unsubscribeRef.current) {
        unsubscribeRef.current();
        unsubscribeRef.current = null;
      }
      if (hoverTimeoutRef.current) {
        clearTimeout(hoverTimeoutRef.current);
      }
      emailCheckCache.current.clear();
      toastShownRef.current = false;
      fuelToastShownRef.current = false;
    };
  }, [driverId, fetchMainTankStock]);

  // Listen for main tank stock updates (hidden from UI)
  useEffect(() => {
    if (!driverId || loading) return;
    
    const companyRef = doc(db, 'company', 'fuelStock');
    const unsubscribe = onSnapshot(companyRef, (docSnap) => {
      if (docSnap.exists()) {
        const data = docSnap.data();
        setMainTankStock(data.stock || { Petrol: 0, Diesel: 0, Kerosene: 0, 'V-Power': 0 });
      }
    }, (error) => {
      console.error('Error listening to main tank:', error);
    });

    return () => unsubscribe();
  }, [driverId, loading]);

  useEffect(() => {
    if (!driverId || loading) return;
    if (unsubscribeRef.current) {
      unsubscribeRef.current();
      unsubscribeRef.current = null;
    }
    unsubscribeRef.current = setupRealtimeListener();
    return () => {
      if (unsubscribeRef.current) {
        unsubscribeRef.current();
        unsubscribeRef.current = null;
      }
    };
  }, [driverId, loading]);

  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (statusContainerRef.current && !statusContainerRef.current.contains(event.target as Node)) {
        setShowStatusUpdates(false);
      }
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  const handleMouseEnter = () => {
    if (hoverTimeoutRef.current) clearTimeout(hoverTimeoutRef.current);
    setShowStatusUpdates(false);
  };

  const handleMouseLeave = () => {
    hoverTimeoutRef.current = setTimeout(() => {
      if (statusUpdateMessages.length > 0 && hasReceivedUpdate) {
        setShowStatusUpdates(true);
      }
    }, 100);
  };

  const addStatusUpdate = useCallback((message: string) => {
    setStatusUpdateMessages(prev => [message, ...prev].slice(0, 5));
    setHasReceivedUpdate(true);
    setShowStatusUpdates(true);
  }, []);

  const setupRealtimeListener = useCallback(() => {
    if (!driverId || !isMountedRef.current) return () => {};
    const docRef = doc(db, 'drivers', driverId);
    
    return onSnapshot(docRef, (docSnap) => {
      if (!isMountedRef.current || !docSnap.exists()) return;
      const data = docSnap.data();
      
      let statusChanged = false;
      let statusMessage = '';
      let fuelChanged = false;
      let fuelMessage = '';

      setFormData(prev => {
        const isOnlineChanged = prev.isOnline !== data.isOnline;
        const statusChangedLocal = prev.status !== data.status;
        
        if ((isOnlineChanged || statusChangedLocal) && !toastShownRef.current) {
          statusChanged = true;
          statusMessage = `⚠️ Driver status updated to ${data.isOnline ? '🟢 Online' : '⚪ Offline'} (from driver app)`;
          addStatusUpdate(statusMessage);
          toastShownRef.current = true;
          setTimeout(() => { toastShownRef.current = false; }, 3000);
        }

        return {
          ...prev,
          isOnline: data.isOnline ?? false,
          status: data.status ?? 'offline',
          isAvailable: data.isAvailable ?? false,
          isApproved: data.isApproved ?? true,
          name: data.name ?? prev.name,
          email: data.email ?? prev.email,
          phone: data.phone ?? prev.phone,
          license: data.license ?? prev.license,
          vehicleType: data.vehicleType ?? prev.vehicleType,
          numberPlate: data.numberPlate ?? prev.numberPlate,
          pricePerKm: data.pricePerKm ?? prev.pricePerKm,
          userType: data.userType ?? 'driver'
        };
      });

      setDriver(prev => {
        if (!prev) return null;
        const oldFuel = prev.remainingFuel;
        const newFuel = data.remainingFuel;
        if (oldFuel && newFuel && !fuelToastShownRef.current) {
          for (const key of Object.keys(newFuel)) {
            const typedKey = key as keyof typeof oldFuel;
            if (oldFuel[typedKey] !== newFuel[typedKey]) {
              fuelChanged = true;
              const diff = (newFuel[typedKey] || 0) - (oldFuel[typedKey] || 0);
              const sign = diff > 0 ? '+' : '';
              fuelMessage = `⚠️ Fuel ${diff > 0 ? 'increased' : 'decreased'}: ${key} ${sign}${diff.toFixed(1)}L`;
              addStatusUpdate(fuelMessage);
              fuelToastShownRef.current = true;
              setTimeout(() => { fuelToastShownRef.current = false; }, 3000);
              break;
            }
          }
        }
        
        return {
          ...prev,
          isOnline: data.isOnline ?? false,
          status: data.status ?? 'offline',
          lastOnlineTime: data.lastOnlineTime ?? prev.lastOnlineTime,
          lastOfflineTime: data.lastOfflineTime ?? prev.lastOfflineTime,
          onlineHistory: data.onlineHistory ?? prev.onlineHistory,
          offlineHistory: data.offlineHistory ?? prev.offlineHistory,
          lastUpdate: data.lastUpdate ?? prev.lastUpdate,
          remainingFuel: data.remainingFuel ?? prev.remainingFuel,
          fuelUpdatedAt: data.fuelUpdatedAt ?? prev.fuelUpdatedAt,
          fuelHistory: data.fuelHistory ?? prev.fuelHistory,
          totalFuelSoldToday: data.totalFuelSoldToday ?? prev.totalFuelSoldToday,
          lastSaleDate: data.lastSaleDate ?? prev.lastSaleDate,
          lastSaleFuelType: data.lastSaleFuelType ?? prev.lastSaleFuelType,
          lastSaleLitres: data.lastSaleLitres ?? prev.lastSaleLitres,
          lastSaleAmount: data.lastSaleAmount ?? prev.lastSaleAmount,
          lastSaleTime: data.lastSaleTime ?? prev.lastSaleTime,
          latitude: data.latitude ?? prev.latitude,
          longitude: data.longitude ?? prev.longitude,
          speed: data.speed ?? prev.speed,
          heading: data.heading ?? prev.heading,
          completedOrders: data.completedOrders ?? prev.completedOrders,
          totalRevenueToday: data.totalRevenueToday ?? prev.totalRevenueToday,
          rating: data.rating ?? prev.rating,
          isApproved: data.isApproved ?? prev.isApproved,
        };
      });

      if (statusChanged && statusMessage && isMountedRef.current) {
        toast.success(statusMessage, { duration: 3000 });
      }
      if (fuelChanged && fuelMessage && isMountedRef.current) {
        toast.success(fuelMessage, { duration: 3000 });
      }
    }, (error) => {
      console.error('❌ Real-time listener error:', error);
      if (isMountedRef.current) toast.error('❌ Connection error. Retrying...');
    });
  }, [driverId, addStatusUpdate]);

  const renderStatusUpdates = () => {
    if (statusUpdateMessages.length === 0 || !showStatusUpdates) return null;
    return (
      <div ref={statusContainerRef} className={`rounded-lg shadow-lg border p-3 transition-all duration-300 animate-in slide-in-from-top-2 ${getCardClass()}`}>
        <div className="flex items-center justify-between mb-2">
          <span className={`text-xs font-medium ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-700'}`}>📡 Live Status Updates</span>
          <span className={`text-xs ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-400'}`}>({statusUpdateMessages.length} updates)</span>
        </div>
        <div className="space-y-1 max-h-24 overflow-y-auto">
          {statusUpdateMessages.map((message, index) => (
            <div key={index} className={`text-xs ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-600'} flex items-center space-x-2`}>
              <span className="w-1.5 h-1.5 bg-green-500 rounded-full flex-shrink-0"></span>
              <span>{message}</span>
              <span className={`text-[10px] ml-auto ${userBackground === 'dark' ? 'text-gray-500' : 'text-gray-400'}`}>{new Date().toLocaleTimeString()}</span>
            </div>
          ))}
        </div>
        <div className={`text-[10px] ${userBackground === 'dark' ? 'text-gray-500' : 'text-gray-400'} mt-1 text-center border-t ${userBackground === 'dark' ? 'border-gray-700' : 'border-gray-100'} pt-1`}>
           Click anywhere outside or hover to close
        </div>
      </div>
    );
  };

  const fetchDriver = async () => {
    try {
      console.log('🔄 Fetching driver with ID:', driverId);
      const docRef = doc(db, 'drivers', driverId);
      const docSnap = await getDoc(docRef);
      
      if (docSnap.exists()) {
        const data = docSnap.data();
        setDriver({ id: docSnap.id, ...data } as DriverData);
        setHasExistingPassword(data.hasPasswordSet || false);
        setFormData({
          name: data.name || '',
          email: data.email || '',
          phone: data.phone || '',
          license: data.license || '',
          vehicleType: data.vehicleType || '',
          numberPlate: data.numberPlate || '',
          isOnline: data.isOnline || false,
          isAvailable: data.isAvailable || false,
          status: data.status || 'offline',
          isApproved: data.isApproved ?? true,
          pricePerKm: data.pricePerKm || 0,
          userType: data.userType || 'driver'
        });
        
        if (data.photoURL) {
          setIsPhotoLoading(true);
          setPhotoPreview(data.photoURL);
          setIsPhotoLoading(false);
        }
      } else {
        toast.error('Driver not found');
        router.push('/drivers');
      }
    } catch (error) {
      console.error('❌ Error fetching driver:', error);
      toast.error('Failed to load driver data');
    } finally {
      setLoading(false);
    }
  };

  const toggleOnlineStatus = async () => {
    setUpdatingStatus(true);
    try {
      const now = new Date().toISOString();
      const docRef = doc(db, 'drivers', driverId);
      const docSnap = await getDoc(docRef);
      
      if (!docSnap.exists()) {
        toast.error('Driver document not found. Please refresh the page.');
        setUpdatingStatus(false);
        return;
      }
      
      const newStatus = !formData.isOnline;
      const historyEntry = {
        timestamp: now,
        status: newStatus ? 'online' : 'offline',
        date: new Date().toLocaleDateString(),
        time: new Date().toLocaleTimeString()
      };

      await updateDoc(docRef, {
        isOnline: newStatus,
        status: newStatus ? 'available' : 'offline',
        lastOnlineTime: newStatus ? now : driver?.lastOnlineTime || null,
        lastOfflineTime: !newStatus ? now : driver?.lastOfflineTime || null,
        onlineHistory: newStatus ? [...(driver?.onlineHistory || []), historyEntry] : driver?.onlineHistory || [],
        offlineHistory: !newStatus ? [...(driver?.offlineHistory || []), historyEntry] : driver?.offlineHistory || [],
        lastUpdate: now
      });

      setFormData(prev => ({ ...prev, isOnline: newStatus, status: newStatus ? 'available' : 'offline' }));
      toast.success(`Driver is now ${newStatus ? '🟢 Online' : '⚪ Offline'}`);
    } catch (error: any) {
      console.error('❌ Error toggling status:', error);
      toast.error(error.code === 'not-found' ? 'Driver document not found. Please refresh and try again.' : 'Failed to update driver status');
    } finally {
      setUpdatingStatus(false);
    }
  };

  const getOfflineDuration = () => {
    if (!driver?.lastOfflineTime) return 'Never offline';
    const offlineTime = new Date(driver.lastOfflineTime);
    const now = new Date();
    const diffMs = now.getTime() - offlineTime.getTime();
    const diffMins = Math.floor(diffMs / 60000);
    const diffHours = Math.floor(diffMins / 60);
    const diffDays = Math.floor(diffHours / 24);
    if (diffDays > 0) return `${diffDays}d ${diffHours % 24}h ago`;
    if (diffHours > 0) return `${diffHours}h ${diffMins % 60}m ago`;
    return `${diffMins}m ago`;
  };

  const getOnlineDuration = () => {
    if (!driver?.lastOnlineTime) return 'Never online';
    const onlineTime = new Date(driver.lastOnlineTime);
    const now = new Date();
    const diffMs = now.getTime() - onlineTime.getTime();
    const diffMins = Math.floor(diffMs / 60000);
    const diffHours = Math.floor(diffMins / 60);
    const diffDays = Math.floor(diffHours / 24);
    if (diffDays > 0) return `${diffDays}d ${diffHours % 24}h`;
    if (diffHours > 0) return `${diffHours}h ${diffMins % 60}m`;
    return `${diffMins}m`;
  };

  const checkEmailExists = useCallback(async (email: string, currentDriverId: string) => {
    if (!email || email.trim() === '') return false;
    if (email.trim().toLowerCase() === driver?.email?.toLowerCase()) return false;
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return false;
    
    const cacheKey = `${email}_${currentDriverId}`;
    if (emailCheckCache.current.has(cacheKey)) return emailCheckCache.current.get(cacheKey) || false;
    
    try {
      const driversRef = collection(db, 'drivers');
      const q = query(driversRef, where('email', '==', email.trim()));
      const querySnapshot = await getDocs(q);
      let exists = false;
      for (const doc of querySnapshot.docs) {
        if (doc.id !== currentDriverId) { exists = true; break; }
      }
      emailCheckCache.current.set(cacheKey, exists);
      return exists;
    } catch (error) {
      console.error('❌ Error checking email:', error);
      return false;
    }
  }, [driver?.email]);

  const handleChange = (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) => {
    const { name, value, type } = e.target;
    let newValue: any = type === 'checkbox' ? (e.target as HTMLInputElement).checked : type === 'number' ? parseFloat(value) || 0 : value;
    
    setFormData(prev => ({ ...prev, [name]: newValue }));
    
    if (name === 'email' && value && driver?.email !== value) {
      checkEmailExists(value, driverId).then(exists => {
        setEmailError(exists);
        if (exists) toast.error('⚠️ This email is already used by another driver!');
      });
    } else if (name === 'email' && value === driver?.email) {
      setEmailError(false);
    }
  };

  const handlePasswordChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const { name, value } = e.target;
    setPasswordData(prev => ({ ...prev, [name]: value }));
  };

  const handleFuelChange = (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) => {
    const { name, value } = e.target;
    const numValue = name === 'amount' ? parseFloat(value) || 0 : value;
    
    const availableFuel = mainTankStock[fuelData.fuelType] || 0;
    
    if (name === 'amount' && numValue > availableFuel && availableFuel > 0) {
      toast.error(` Maximum available is ${availableFuel.toFixed(1)}L for ${fuelData.fuelType}`, {
        duration: 3000,
        icon: ''
      });
      setFuelData(prev => ({ ...prev, [name]: availableFuel }));
      return;
    }
    
    setFuelData(prev => ({ ...prev, [name]: numValue }));
  };

  const handleDeleteDriver = async () => {
    setDeletingDriver(true);
    try {
      const docRef = doc(db, 'drivers', driverId);
      const docSnap = await getDoc(docRef);
      if (!docSnap.exists()) {
        toast.error('Driver document not found. It may have been already deleted.');
        router.push('/drivers');
        setDeletingDriver(false);
        return;
      }
      
      if (driver?.photoURL) {
        try {
          await deleteObject(ref(storage, `drivers/${driverId}/profile`));
        } catch (error) {
          console.error('❌ No photo to delete:', error);
        }
      }
      
      try {
        const authInstance = getAuth();
        const currentUser = authInstance.currentUser;
        if (currentUser && currentUser.uid === driverId) {
          await deleteUser(currentUser);
        } else {
          toast.error('⚠️ Auth account deletion requires Admin SDK. Please use Firebase Console for auth cleanup.', { duration: 5000 });
        }
      } catch (authError) {
        console.log('ℹ️ Could not delete from Auth:', authError);
      }
      
      await deleteDoc(docRef);
      toast.success('Driver deleted successfully!');
      router.push('/drivers');
    } catch (error: any) {
      console.error('❌ Error deleting driver:', error);
      toast.error(error.code === 'not-found' ? 'Driver document not found. It may have been already deleted.' : 'Failed to delete driver: ' + (error.message || 'Please try again'));
    } finally {
      setDeletingDriver(false);
      setShowDeleteModal(false);
    }
  };

  // ✅ FIXED: handleFuelTopUp with correct adminName from logged-in user
  const handleFuelTopUp = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!fuelData.fuelType || fuelData.amount <= 0) {
      toast.error('Please select a fuel type and enter a valid amount');
      return;
    }
    if (!driver?.remainingFuel) {
      toast.error('Driver fuel data not found');
      return;
    }

    setUpdatingFuel(true);
    try {
      const amount = fuelData.amount;
      const fuelType = fuelData.fuelType;
      const companyRef = doc(db, 'company', 'fuelStock');
      const driverRef = doc(db, 'drivers', driverId);

      // ✅ Get the current logged-in user for admin name
      const currentUser = auth.currentUser;
      let adminName = 'Admin';
      let adminId = 'admin';
      
      if (currentUser) {
        adminId = currentUser.uid;
        // Try to get display name, fallback to email or 'Admin'
        if (currentUser.displayName) {
          adminName = currentUser.displayName;
        } else if (currentUser.email) {
          adminName = currentUser.email.split('@')[0];
        }
        
        // Try to get full name from users collection
        try {
          const userDoc = await getDoc(doc(db, 'users', currentUser.uid));
          if (userDoc.exists()) {
            const userData = userDoc.data();
            if (userData.name) {
              adminName = userData.name;
            } else if (userData.displayName) {
              adminName = userData.displayName;
            }
          }
        } catch (error) {
          console.log('ℹ️ Could not fetch user display name, using fallback:', error);
        }
      }

      const result = await runTransaction(db, async (transaction) => {
        const companySnap = await transaction.get(companyRef);
        if (!companySnap.exists()) {
          throw new Error('Company fuel stock document not found');
        }

        const companyData = companySnap.data();
        const currentMainStock = companyData.stock || { Petrol: 0, Diesel: 0, Kerosene: 0, 'V-Power': 0 };
        const mainTankAmount = currentMainStock[fuelType] || 0;

        if (mainTankAmount < amount) {
          throw new Error(`INSUFFICIENT_FUEL:${mainTankAmount}:${amount}`);
        }

        const driverSnap = await transaction.get(driverRef);
        if (!driverSnap.exists()) {
          throw new Error('Driver document not found');
        }

        const driverData = driverSnap.data();
        const driverFuel = driverData.remainingFuel || { Petrol: 0, Diesel: 0, Kerosene: 0, 'V-Power': 0 };
        const currentDriverFuel = driverFuel[fuelType] || 0;
        const newDriverFuel = currentDriverFuel + amount;
        const newMainStock = mainTankAmount - amount;

        if (newMainStock < 0) {
          throw new Error(`INSUFFICIENT_FUEL:${mainTankAmount}:${amount}`);
        }

        // ✅ FIXED: Use the adminName from logged-in user, NOT the driver's name
        const newHistoryEntry = {
          fuelType: fuelType,
          amount: amount,
          previousAmount: currentDriverFuel,
          newAmount: newDriverFuel,
          note: fuelData.note || 'Admin top-up from main tank',
          timestamp: new Date().toISOString(),
          adminId: adminId,
          adminName: adminName,  // ✅ This is the logged-in admin's name
          action: 'top-up',
          source: 'main-tank',
          mainTankBefore: mainTankAmount,
          mainTankAfter: newMainStock
        };

        // ✅ FIXED: Also ensure company log uses the correct admin name
        const companyLogEntry = {
          fuelType: fuelType,
          amount: amount,
          action: 'deduct',
          actionType: 'Driver Top-up',
          reason: `Driver ${driverData.name || driverId} topped up ${amount}L ${fuelType}`,
          timestamp: new Date().toISOString(),
          date: new Date().toLocaleString(),
          previousTankAmount: mainTankAmount,
          newTankAmount: newMainStock,
          updatedBy: adminName,  // ✅ Use adminName, not driver name
          driverId: driverId,
          driverName: driverData.name || 'Unknown Driver',
          capacityInfo: `${newMainStock}/100000L`
        };

        const updatedMainStock = {
          ...currentMainStock,
          [fuelType]: newMainStock
        };

        const existingLogs = companyData.activityLog || [];
        const updatedLogs = [companyLogEntry, ...existingLogs].slice(0, 100);

        transaction.update(companyRef, {
          stock: updatedMainStock,
          activityLog: updatedLogs,
          lastUpdated: new Date().toISOString()
        });

        const updatedDriverFuel = {
          ...driverFuel,
          [fuelType]: newDriverFuel
        };

        const driverHistory = driverData.fuelHistory || [];
        const updatedDriverHistory = [newHistoryEntry, ...driverHistory].slice(0, 50);

        transaction.update(driverRef, {
          remainingFuel: updatedDriverFuel,
          fuelUpdatedAt: new Date().toISOString(),
          fuelHistory: updatedDriverHistory,
          lastUpdate: new Date().toISOString()
        });

        return {
          success: true,
          mainTankBefore: mainTankAmount,
          mainTankAfter: newMainStock,
          driverFuelBefore: currentDriverFuel,
          driverFuelAfter: newDriverFuel,
          amount: amount,
          fuelType: fuelType,
          adminName: adminName
        };
      });

      if (result.success) {
        setMainTankStock(prev => ({
          ...prev,
          [result.fuelType]: result.mainTankAfter
        }));

        setDriver(prev => {
          if (!prev) return null;
          const updatedFuel = {
            ...prev.remainingFuel!,
            [result.fuelType]: result.driverFuelAfter
          };
          return {
            ...prev,
            remainingFuel: updatedFuel,
            fuelUpdatedAt: new Date().toISOString()
          };
        });

        toast.success(`✅ ${result.amount}L of ${result.fuelType} added to driver by ${result.adminName}!`, {
          duration: 4000,
          icon: ''
        });

        setShowFuelModal(false);
        setFuelData({ fuelType: 'Petrol', amount: 0, note: '' });
      }
    } catch (error: any) {
      console.error(' Error topping up fuel:', error);
      
      if (error.message && error.message.includes('INSUFFICIENT_FUEL')) {
        const parts = error.message.split(':');
        if (parts.length === 3) {
          const available = parseFloat(parts[1]);
          const requested = parseFloat(parts[2]);
          toast.error(` Not enough fuel in main tank! Available: ${available.toFixed(1)}L, Requested: ${requested.toFixed(1)}L. Please reduce the amount or import more fuel.`, {
            duration: 5000,
            icon: ''
          });
        } else {
          toast.error(` Not enough fuel in main tank! Please reduce the amount or import more fuel.`, {
            duration: 5000,
            icon: ''
          });
        }
      } else {
        toast.error(error.message || 'Failed to add fuel to driver');
      }
    } finally {
      setUpdatingFuel(false);
    }
  };

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) { toast.error('No file selected'); return; }
    if (!file.type.startsWith('image/')) { toast.error('Please select an image file (JPEG, PNG, etc.)'); return; }
    if (file.size > 5 * 1024 * 1024) { toast.error('Image must be less than 5MB'); return; }

    setSelectedFile(file);
    setUploadProgress(0);
    const reader = new FileReader();
    reader.onload = (event) => {
      setPhotoPreview(event.target?.result as string);
      toast.success('Photo selected! Click "Save Photo" to upload permanently.');
    };
    reader.onerror = () => toast.error('Failed to read file');
    reader.readAsDataURL(file);
  };

  const handleSavePhoto = async () => {
    if (!selectedFile || !driverId) { toast.error('No file selected'); return; }

    setUploadingPhoto(true);
    setUploadProgress(0);

    try {
      const docRef = doc(db, 'drivers', driverId);
      const docSnap = await getDoc(docRef);
      if (!docSnap.exists()) {
        toast.error('Driver document not found. Please refresh the page.');
        setUploadingPhoto(false);
        return;
      }
      
      if (driver?.photoURL) {
        try {
          await deleteObject(ref(storage, `drivers/${driverId}/profile`));
        } catch (error) {
          console.log('ℹ️ No old photo to delete:', error);
        }
      }

      const fileExtension = selectedFile.name.split('.').pop() || 'jpg';
      const storageRef = ref(storage, `drivers/${driverId}/profile.${fileExtension}`);
      const uploadTask = uploadBytesResumable(storageRef, selectedFile, { contentType: selectedFile.type });

      uploadTask.on(
        'state_changed',
        (snapshot) => {
          if (!isMountedRef.current) return;
          setUploadProgress(Math.round((snapshot.bytesTransferred / snapshot.totalBytes) * 100));
        },
        (error) => {
          if (!isMountedRef.current) return;
          console.error('❌ Upload error:', error);
          toast.error('Upload failed: ' + (error.message || 'Unknown error'));
          setUploadingPhoto(false);
          setUploadProgress(0);
        },
        async () => {
          if (!isMountedRef.current) return;
          try {
            const downloadURL = await getDownloadURL(uploadTask.snapshot.ref);
            await updateDoc(docRef, {
              photoURL: downloadURL,
              driverPhoto: downloadURL,
              updatedAt: new Date().toISOString(),
              lastUpdate: new Date().toISOString()
            });

            setPhotoPreview(downloadURL);
            setSelectedFile(null);
            setUploadProgress(100);
            if (fileInputRef.current) fileInputRef.current.value = '';
            toast.success('Photo uploaded and saved successfully!');
          } catch (error: any) {
            console.error('❌ Error after upload:', error);
            toast.error('Failed to save photo: ' + (error.message || 'Try again'));
          } finally {
            setUploadingPhoto(false);
          }
        }
      );
    } catch (error: any) {
      console.error('❌ Save error:', error);
      toast.error('Failed to save photo: ' + (error.message || 'Try again'));
      setUploadingPhoto(false);
      setUploadProgress(0);
    }
  };

  const handleRemovePhoto = async () => {
    if (!driver?.photoURL) return;
    if (!confirm('Remove this photo?')) return;

    try {
      const docRef = doc(db, 'drivers', driverId);
      const docSnap = await getDoc(docRef);
      if (!docSnap.exists()) {
        toast.error('Driver document not found. Please refresh the page.');
        return;
      }
      
      await deleteObject(ref(storage, `drivers/${driverId}/profile`));
      await updateDoc(docRef, { photoURL: null, driverPhoto: null, updatedAt: new Date().toISOString() });
      setPhotoPreview(null);
      setSelectedFile(null);
      if (fileInputRef.current) fileInputRef.current.value = '';
      toast.success('Photo removed successfully');
    } catch (error) {
      console.error('❌ Remove error:', error);
      toast.error('Failed to remove photo');
    }
  };

  const formatPhoneNumber = (phone: string): string => {
    let cleaned = phone.replace(/[^0-9]/g, '');
    if (cleaned.startsWith('0') && cleaned.length >= 10) return cleaned;
    if (cleaned.startsWith('254') && cleaned.length >= 12) return '0' + cleaned.substring(3);
    if (cleaned.length >= 9) return '0' + cleaned;
    return phone;
  };

  const handleUpdatePassword = async (e: React.FormEvent) => {
    e.preventDefault();
    
    if (!passwordData.newPassword || !passwordData.confirmPassword) {
      toast.error('Please fill in both password fields');
      return;
    }
    if (passwordData.newPassword !== passwordData.confirmPassword) {
      toast.error('New passwords do not match');
      return;
    }
    if (passwordData.newPassword.length < 6) {
      toast.error('Password must be at least 6 characters');
      return;
    }

    setUpdatingPassword(true);
    try {
      const currentUser = auth.currentUser;
      
      if (!currentUser) {
        toast.error('You must be logged in as admin to change driver passwords');
        setUpdatingPassword(false);
        return;
      }

      const driverEmail = driver?.email;
      const driverName = driver?.name;

      if (!driverEmail) {
        toast.error('Driver email not found. Please update the email first.');
        setUpdatingPassword(false);
        return;
      }

      try {
        const userCredential = await createUserWithEmailAndPassword(
          auth, 
          driverEmail, 
          passwordData.newPassword
        );
        
        const uid = userCredential.user.uid;
        await updateProfile(userCredential.user, { displayName: driverName || '' });
        
        const driverRef = doc(db, 'drivers', driverId);
        await updateDoc(driverRef, {
          hasPasswordSet: true,
          authUserId: uid,
          userId: uid,
          passwordUpdatedAt: new Date().toISOString()
        });

        setHasExistingPassword(true);
        toast.success(`✅ Password created successfully for ${driverName}!`, {
          duration: 4000,
          icon: ''
        });

        setShowPasswordModal(false);
        setPasswordData({ newPassword: '', confirmPassword: '' });
        setUpdatingPassword(false);
        return;

      } catch (error: any) {
        if (error.code === 'auth/email-already-in-use') {
          try {
            await sendPasswordResetEmail(auth, driverEmail);
            
            const driverRef = doc(db, 'drivers', driverId);
            await updateDoc(driverRef, {
              passwordResetSent: new Date().toISOString(),
              hasPasswordSet: true,
              needsPasswordReset: true
            });

            toast.success(`📧 Password reset email sent to ${driverEmail}`, {
              duration: 5000,
              icon: '📧'
            });
            
            toast.info('The driver will receive an email to set their own password.', {
              duration: 4000,
              icon: 'ℹ️'
            });

            setShowPasswordModal(false);
            setPasswordData({ newPassword: '', confirmPassword: '' });
            
          } catch (resetError: any) {
            console.error(' Reset email error:', resetError);
            
            if (resetError.code === 'auth/user-not-found') {
              toast.error('Driver account not found. Please create the account first.');
            } else if (resetError.code === 'auth/too-many-requests') {
              toast.error('Too many requests. Please try again later.');
            } else {
              toast.error('Failed to send reset email: ' + (resetError.message || 'Unknown error'));
            }
          }
          setUpdatingPassword(false);
          return;
        } else {
          throw error;
        }
      }

    } catch (error: any) {
      console.error(' Error updating password:', error);
      if (error.code === 'auth/weak-password') {
        toast.error('Password is too weak. Use at least 6 characters with a mix of letters and numbers.');
      } else if (error.code === 'auth/email-already-in-use') {
        toast.error(' Email already registered. A reset email has been sent.');
      } else if (error.code === 'auth/too-many-requests') {
        toast.error('Too many requests. Please try again later.');
      } else {
        toast.error('Failed to update password: ' + (error.message || 'Unknown error'));
      }
    } finally {
      setUpdatingPassword(false);
    }
  };

  const createDriverAccount = async (email: string, password: string, name: string, phone: string) => {
    try {
      const authInstance = auth;
      try {
        const userCredential = await createUserWithEmailAndPassword(authInstance, email, password);
        const uid = userCredential.user.uid;
        await updateProfile(userCredential.user, { displayName: name });
        
        const formattedPhone = formatPhoneNumber(phone);
        const driverRef = doc(db, 'drivers', driverId);
        const docSnap = await getDoc(driverRef);
        
        if (!docSnap.exists()) {
          await setDoc(doc(db, 'drivers', uid), {
            userId: uid,
            name,
            phone: formattedPhone,
            email,
            userType: 'driver',
            vehicleType: formData.vehicleType || 'Pending Assignment',
            numberPlate: formData.numberPlate || 'Pending Assignment',
            pricePerKm: formData.pricePerKm || 0,
            license: formData.license || '',
            isApproved: true,
            isOnline: false,
            isAvailable: false,
            status: 'offline',
            orderAccepted: false,
            lat: 0.0,
            lng: 0.0,
            heading: 0.0,
            speed: 0.0,
            latitude: 0.0,
            longitude: 0.0,
            activeOrderId: null,
            orderStartedAt: null,
            currentClientName: null,
            currentClientPhone: null,
            currentClientLocation: null,
            currentClientPhoto: null,
            remainingFuel: { Petrol: 0.0, Diesel: 0.0, Kerosene: 0.0, 'V-Power': 0.0 },
            fuelUpdatedAt: new Date().toISOString(),
            fuelHistory: [],
            salesHistory: [],
            totalFuelSoldToday: 0.0,
            totalRevenueToday: 0.0,
            lastSaleDate: null,
            lastSaleFuelType: null,
            lastSaleLitres: 0.0,
            lastSaleAmount: 0.0,
            lastSaleTime: null,
            lastOrderTime: null,
            totalOrders: 0,
            completedOrders: 0,
            lastCompletedOrderAt: null,
            onlineHistory: [],
            lastOnlineTime: null,
            lastOfflineTime: null,
            lastUpdate: new Date().toISOString(),
            profileComplete: true,
            driverPhoto: userCredential.user?.photoURL || '',
            photoURL: userCredential.user?.photoURL || '',
            rating: 0.0,
            driverSince: new Date().toISOString(),
            createdAt: new Date().toISOString(),
            updatedAt: new Date().toISOString(),
            hasPasswordSet: true,
            authUserId: uid,
            passwordUpdatedAt: new Date().toISOString()
          });
        } else {
          await updateDoc(driverRef, {
            hasPasswordSet: true,
            authUserId: uid,
            userId: uid,
            passwordUpdatedAt: new Date().toISOString()
          });
        }
        return { success: true, uid };
      } catch (error: any) {
        if (error.code === 'auth/email-already-in-use') {
          try {
            const userCredential = await signInWithEmailAndPassword(authInstance, email, password);
            const driverUser = authInstance.currentUser;
            if (driverUser) {
              await updatePassword(driverUser, password);
              const driverRef = doc(db, 'drivers', driverId);
              const docSnap = await getDoc(driverRef);
              if (docSnap.exists()) {
                await updateDoc(driverRef, {
                  hasPasswordSet: true,
                  authUserId: driverUser.uid,
                  userId: driverUser.uid,
                  passwordUpdatedAt: new Date().toISOString()
                });
              } else {
                await setDoc(doc(db, 'drivers', driverUser.uid), {
                  userId: driverUser.uid,
                  name,
                  phone: formatPhoneNumber(phone),
                  email,
                  userType: 'driver',
                  hasPasswordSet: true,
                  authUserId: driverUser.uid,
                  passwordUpdatedAt: new Date().toISOString()
                });
              }
              return { success: true, uid: driverUser.uid };
            }
          } catch (signInError) {
            const driversRef = collection(db, 'drivers');
            const q = query(driversRef, where('email', '==', email));
            const querySnapshot = await getDocs(q);
            if (!querySnapshot.empty) {
              await updateDoc(doc(db, 'drivers', querySnapshot.docs[0].id), {
                hasPasswordSet: true,
                passwordUpdatedAt: new Date().toISOString()
              });
            }
            return { success: true, uid: null, needsReset: true, message: 'Account exists with this email. Driver may need to use "Forgot Password".' };
          }
        } else {
          throw error;
        }
      }
      return { success: true };
    } catch (error: any) {
      console.error(' Error creating driver account:', error);
      throw error;
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);

    try {
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(formData.email)) {
        toast.error('Please enter a valid email address');
        setSaving(false);
        return;
      }

      const docRef = doc(db, 'drivers', driverId);
      const docSnap = await getDoc(docRef);
      if (!docSnap.exists()) {
        toast.error('Driver document not found. Please refresh the page.');
        setSaving(false);
        return;
      }
      
      const currentEmail = driver?.email;
      const newEmail = formData.email;
      if (currentEmail !== newEmail && newEmail) {
        const emailExists = await checkEmailExists(newEmail, driverId);
        if (emailExists) {
          toast.error('❌ This email is already used by another driver.');
          setSaving(false);
          setEmailError(true);
          return;
        }
      }
      
      await updateDoc(docRef, {
        name: formData.name,
        email: formData.email,
        phone: formData.phone,
        license: formData.license,
        vehicleType: formData.vehicleType,
        numberPlate: formData.numberPlate,
        isOnline: formData.isOnline,
        isAvailable: formData.isAvailable,
        status: formData.status,
        isApproved: formData.isApproved,
        pricePerKm: formData.pricePerKm,
        userType: 'driver',
        updatedAt: new Date().toISOString(),
        lastUpdate: new Date().toISOString()
      });

      toast.success('Driver updated successfully!');
      router.push('/drivers');
    } catch (error: any) {
      console.error('Error updating driver:', error);
      toast.error(error.code === 'not-found' ? 'Driver document not found. Please refresh the page.' : 'Failed to update driver');
    } finally {
      setSaving(false);
    }
  };

  // Driver Location Display
  const DriverLocationDisplay = useMemo(() => {
    if (driver?.latitude === undefined || driver?.longitude === undefined) return null;
    return (
      <div className="p-4 rounded-lg border shadow-sm bg-gradient-to-br from-blue-500 to-indigo-600 text-white">
        <div className="flex items-center justify-between">
          <h3 className="text-sm font-medium text-white"> Live Location (from Flutter)</h3>
          <span className="text-xs text-blue-200 animate-pulse">● Live</span>
        </div>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mt-2">
          <div>
            <p className="text-xs text-blue-200">Latitude</p>
            <p className="text-sm font-medium text-white">{driver.latitude}</p>
          </div>
          <div>
            <p className="text-xs text-blue-200">Longitude</p>
            <p className="text-sm font-medium text-white">{driver.longitude}</p>
          </div>
          {driver.speed !== undefined && (
            <div>
              <p className="text-xs text-blue-200">Speed</p>
              <p className="text-sm font-medium text-white">{driver.speed} km/h</p>
            </div>
          )}
          {driver.heading !== undefined && (
            <div>
              <p className="text-xs text-blue-200">Heading</p>
              <p className="text-sm font-medium text-white">{driver.heading}°</p>
            </div>
          )}
        </div>
        {driver.lastUpdate && (
          <p className="text-xs text-blue-200 mt-3"> Last update: {new Date(driver.lastUpdate).toLocaleString()}</p>
        )}
      </div>
    );
  }, [driver?.latitude, driver?.longitude, driver?.speed, driver?.heading, driver?.lastUpdate]);

  // RealTimeStatusIndicator
  const RealTimeStatusIndicator = () => (
    <div className="flex items-center gap-2">
      <div className="w-2 h-2 rounded-full animate-pulse bg-blue-500"></div>
      <span className="text-xs text-blue-600">Live - Real-time sync active</span>
    </div>
  );

  if (loading) {
    return (
      <div className={`flex items-center justify-center min-h-[60vh] ${getBackgroundClass()}`}>
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-green-500"></div>
      </div>
    );
  }

  if (!driver) {
    return (
      <div className={`text-center py-12 ${getBackgroundClass()}`}>
        <h2 className={`text-2xl font-bold ${userBackground === 'dark' ? 'text-white' : 'text-gray-800'}`}>Driver Not Found</h2>
        <p className={`mt-2 ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>The driver you're looking for doesn't exist.</p>
        <Link href="/drivers" className="mt-4 inline-block text-green-600 hover:text-green-800">← Back to Drivers</Link>
      </div>
    );
  }

  return (
    <div className={`p-4 md:p-6 transition-colors duration-300 ${getBackgroundClass()}`}>
      <div className="max-w-7xl mx-auto space-y-6">
        <div className="flex items-center justify-between">
          <div>
            <h1 className={`text-2xl font-bold ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'}`}>Edit Driver</h1>
            <p className={`text-sm ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>Update driver information</p>
          </div>
          <div className="flex items-center gap-4">
            <RealTimeStatusIndicator />
            <Link href="/drivers" className={`text-sm ${userBackground === 'dark' ? 'text-gray-400 hover:text-gray-200' : 'text-gray-500 hover:text-gray-700'} flex items-center space-x-1`}>
              <span>←</span>
              <span>Back to Drivers</span>
            </Link>
          </div>
        </div>

        <div ref={statusContainerRef} onMouseEnter={handleMouseEnter} onMouseLeave={handleMouseLeave} className="relative cursor-default">
          {renderStatusUpdates()}
        </div>

        {/* Status Card */}
        <div className="rounded-xl shadow-sm p-4 border bg-red-100 border-red-200">
          <div className="flex items-center justify-between flex-wrap gap-4">
            <div className="flex items-center space-x-4">
              <div className="flex items-center space-x-2">
                <div className={`w-3 h-3 rounded-full ${formData.isOnline ? 'bg-green-500 animate-pulse' : 'bg-gray-400'}`}></div>
                <span className={`font-medium ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'}`}>
                  {formData.isOnline ? '🟢 Online' : '⚪ Offline'}
                </span>
                <span className={`text-xs ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-400'} ml-2`}>(Live from driver app)</span>
              </div>
              {formData.isOnline ? (
                <span className={`text-sm ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-500'}`}>Online for: <span className="font-medium text-green-600">{getOnlineDuration()}</span></span>
              ) : (
                <span className={`text-sm ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-500'}`}>Offline for: <span className="font-medium text-red-600">{getOfflineDuration()}</span></span>
              )}
            </div>
            <div className="flex items-center gap-3">
              {driver?.lastUpdate && (
                <span className={`text-xs ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-400'}`}>Updated: {new Date(driver.lastUpdate).toLocaleTimeString()}</span>
              )}
              <button
                onClick={toggleOnlineStatus}
                disabled={updatingStatus}
                className={`px-4 py-2 rounded-lg text-sm font-medium transition ${
                  formData.isOnline ? 'bg-red-500 hover:bg-red-600 text-white' : 'bg-green-500 hover:bg-green-600 text-white'
                } disabled:opacity-50`}
              >
                {updatingStatus ? (
                  <span className="flex items-center space-x-2">
                    <svg className="animate-spin h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                      <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                      <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                    </svg>
                    <span>Updating...</span>
                  </span>
                ) : (
                  formData.isOnline ? '🔴 Go Offline' : '🟢 Go Online'
                )}
              </button>
            </div>
          </div>
        </div>

        {DriverLocationDisplay}

        <div className={`rounded-xl shadow-sm p-6 border ${userBackground === 'dark' ? 'border-gray-700' : 'border-gray-100'} ${getCardClass()}`}>
          <form onSubmit={handleSubmit} className="space-y-6">
            <div className="flex flex-col items-center space-y-4 pb-6 border-b border-gray-200">
              <div className="flex justify-between w-full">
                <h3 className={`text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'}`}>Profile Photo</h3>
                <span className={`text-xs ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-400'}`}>Syncs to Flutter automatically</span>
              </div>
              <div className="flex flex-col items-center space-y-4">
                <div className="relative">
                  <div className={`w-32 h-32 rounded-full overflow-hidden ${userBackground === 'dark' ? 'bg-gray-700' : 'bg-gray-100'} border-2 ${userBackground === 'dark' ? 'border-gray-600' : 'border-gray-200'}`}>
                    {isPhotoLoading ? (
                      <div className="w-full h-full flex items-center justify-center">
                        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-green-500"></div>
                      </div>
                    ) : photoPreview ? (
                      <img 
                        src={photoPreview} 
                        alt={`${driver.name}'s profile`} 
                        className="w-full h-full object-cover"
                        onError={(e) => {
                          const target = e.target as HTMLImageElement;
                          target.style.display = 'none';
                          const parent = target.parentElement;
                          if (parent) {
                            const fallback = document.createElement('div');
                            fallback.className = 'w-full h-full flex items-center justify-center bg-gray-100';
                            fallback.innerHTML = `<span class="text-4xl text-gray-400">${driver.name?.charAt(0)?.toUpperCase() || '?'}</span>`;
                            parent.appendChild(fallback);
                          }
                          setIsPhotoLoading(false);
                        }}
                      />
                    ) : (
                      <div className={`w-full h-full flex items-center justify-center ${userBackground === 'dark' ? 'bg-gray-700' : 'bg-gray-100'}`}>
                        <span className={`text-4xl ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-400'}`}>
                          {driver.name?.charAt(0)?.toUpperCase() || '?'}
                        </span>
                      </div>
                    )}
                  </div>
                  {uploadingPhoto && (
                    <div className="absolute inset-0 bg-black bg-opacity-50 rounded-full flex items-center justify-center">
                      <div className="flex flex-col items-center">
                        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-white"></div>
                        <span className="text-white text-xs mt-1">{uploadProgress}%</span>
                      </div>
                    </div>
                  )}
                </div>

                <div className="flex flex-wrap gap-3 justify-center">
                  <input type="file" ref={fileInputRef} onChange={handleFileSelect} accept="image/jpeg,image/png,image/gif,image/webp" className="hidden" />
                  <button type="button" onClick={() => fileInputRef.current?.click()} disabled={uploadingPhoto} className="px-4 py-2 text-sm font-medium text-white bg-blue-500 rounded-lg hover:bg-blue-600 transition disabled:opacity-50">📁 Select Photo</button>
                  {selectedFile && !uploadingPhoto && (
                    <button type="button" onClick={handleSavePhoto} className="px-4 py-2 text-sm font-medium text-white bg-green-500 rounded-lg hover:bg-green-600 transition">💾 Save Photo</button>
                  )}
                  {uploadingPhoto && (
                    <button type="button" disabled className="px-4 py-2 text-sm font-medium text-white bg-gray-500 rounded-lg cursor-not-allowed">⏳ Uploading...</button>
                  )}
                  {driver.photoURL && !selectedFile && !uploadingPhoto && (
                    <button type="button" onClick={handleRemovePhoto} className="px-4 py-2 text-sm font-medium text-white bg-red-500 rounded-lg hover:bg-red-600 transition">❌ Remove</button>
                  )}
                </div>
                {selectedFile && !uploadingPhoto && (
                  <p className="text-xs text-green-600">📄 {selectedFile.name} ({(selectedFile.size / 1024).toFixed(1)} KB) - Ready to upload</p>
                )}
                {driver.photoURL && !selectedFile && (
                  <div className="text-center">
                    <p className="text-xs text-green-600">✅ Photo is saved and synced to Flutter</p>
                  </div>
                )}
                {uploadProgress > 0 && uploadProgress < 100 && (
                  <div className="w-full max-w-xs bg-gray-200 rounded-full h-2.5">
                    <div className="bg-green-500 h-2.5 rounded-full transition-all duration-300" style={{ width: `${uploadProgress}%` }}></div>
                  </div>
                )}
                <p className={`text-xs ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>Max 5MB (JPEG, PNG, GIF, WebP)</p>
              </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div>
                <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-2`}>Full Name *</label>
                <input type="text" name="name" value={formData.name} onChange={handleChange} required className={`w-full px-4 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500 ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'}`} placeholder="John Doe" />
              </div>
              <div>
                <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-2`}>Email Address *</label>
                <input type="email" name="email" value={formData.email} onChange={handleChange} required className={`w-full px-4 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500 ${emailError ? 'border-red-500 bg-red-50' : userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'}`} placeholder="john@example.com" />
                {emailError && <p className="text-xs text-red-500 mt-1">⚠️ This email is already used by another driver!</p>}
              </div>
              <div>
                <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-2`}>Phone Number *</label>
                <input type="tel" name="phone" value={formData.phone} onChange={handleChange} required className={`w-full px-4 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500 ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'}`} placeholder="0712345678" />
              </div>
              <div>
                <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-2`}>License Number</label>
                <input type="text" name="license" value={formData.license} onChange={handleChange} className={`w-full px-4 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500 ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'}`} placeholder="DL-123456" />
              </div>
              <div>
                <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-2`}>Vehicle Type</label>
                <input type="text" name="vehicleType" value={formData.vehicleType} onChange={handleChange} className={`w-full px-4 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500 ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'}`} placeholder="e.g., Truck, Van, Car" />
              </div>
              <div>
                <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-2`}>Number Plate</label>
                <input type="text" name="numberPlate" value={formData.numberPlate} onChange={handleChange} className={`w-full px-4 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500 ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'}`} placeholder="e.g., KCA 123A" />
              </div>
              <div>
                <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-2`}>Status</label>
                <select name="status" value={formData.status} onChange={handleChange} className={`w-full px-4 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500 ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'}`}>
                  <option value="available">Available</option>
                  <option value="busy">Busy</option>
                  <option value="offline">Offline</option>
                  <option value="on_break">On Break</option>
                </select>
              </div>
              <div>
                <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-2`}>Price Per Km (KES)</label>
                <input type="number" name="pricePerKm" value={formData.pricePerKm} onChange={handleChange} step="0.01" className={`w-full px-4 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500 ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'}`} placeholder="0.00" />
              </div>
            </div>

            {driver && (
              <div className={`p-4 rounded-lg border ${userBackground === 'dark' ? 'bg-gray-700 border-gray-600' : 'bg-cyan-500 border-gray-200'}`}>
                <h3 className={`text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-3`}>Driver Statistics</h3>
                <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                  <div>
                    <p className={`text-xs ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>Completed Orders</p>
                    <p className={`text-lg font-bold ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'}`}>{driver.completedOrders || 0}</p>
                  </div>
                  <div>
                    <p className={`text-xs ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>Today's Revenue</p>
                    <p className={`text-lg font-bold ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'}`}>KES {driver.totalRevenueToday?.toLocaleString() || 0}</p>
                  </div>
                  <div>
                    <p className={`text-xs ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>Rating</p>
                    <p className={`text-lg font-bold ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'}`}>{driver.rating || 0} ⭐</p>
                  </div>
                  <div>
                    <p className={`text-xs ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>Driver ID</p>
                    <p className={`text-sm font-mono ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-900'}`}>{driver.id.slice(0, 12)}...</p>
                  </div>
                </div>
              </div>
            )}

            {driver?.remainingFuel && (
              <div className={`p-4 rounded-lg border ${userBackground === 'dark' ? 'bg-gray-700 border-gray-600' : 'bg-gray-50 border-gray-200'}`}>
                <div className="flex items-center justify-between mb-3">
                  <h3 className={`text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'}`}> Driver Fuel Stock</h3>
                  <button type="button" onClick={() => setShowFuelModal(true)} className="px-3 py-1 text-xs font-medium text-white bg-green-500 rounded-lg hover:bg-green-600 transition">+ Top Up Fuel</button>
                </div>
                <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                  {Object.entries(driver.remainingFuel).map(([type, amount]) => (
                    <div key={type} className={`p-3 rounded-lg shadow-sm ${userBackground === 'dark' ? 'bg-gray-800' : 'bg-red-900'}`}>
                      <p className={`text-xs ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-400'}`}>{type}</p>
                      <p className={`text-lg font-bold ${userBackground === 'dark' ? 'text-white' : 'text-gray-200'}`}>{Number(amount).toLocaleString()}L</p>
                    </div>
                  ))}
                </div>
                {driver.fuelHistory && driver.fuelHistory.length > 0 && (
                  <div className="mt-3 pt-3 border-t border-gray-200">
                    <p className={`text-xs ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-400'}`}>
                      Last top-up: {driver.fuelHistory[driver.fuelHistory.length - 1]?.timestamp 
                        ? new Date(driver.fuelHistory[driver.fuelHistory.length - 1].timestamp).toLocaleString() 
                        : 'N/A'}
                    </p>
                  </div>
                )}
              </div>
            )}

            {driver && (
              <div className={`p-4 rounded-lg border ${userBackground === 'dark' ? 'bg-blue-900/30 border-blue-700' : 'bg-blue-50 border-blue-200'}`}>
                <h3 className={`text-sm font-medium ${userBackground === 'dark' ? 'text-blue-300' : 'text-blue-800'} mb-3`}>👁️ Driver Preview (How clients see you)</h3>
                <div className="flex items-center space-x-4">
                  <div className="w-16 h-16 rounded-full overflow-hidden bg-gray-200 border-2 border-blue-300 flex-shrink-0">
                    {driver.photoURL ? (
                      <img src={driver.photoURL} alt={driver.name} className="w-full h-full object-cover" onError={(e) => { (e.target as HTMLImageElement).style.display = 'none'; }} />
                    ) : (
                      <div className="w-full h-full flex items-center justify-center bg-gray-200">
                        <span className="text-xl text-gray-500">{driver.name?.charAt(0)?.toUpperCase()}</span>
                      </div>
                    )}
                  </div>
                  <div>
                    <p className={`font-medium ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'}`}>{driver.name}</p>
                    <p className={`text-sm ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-600'}`}>📱 {driver.phone}</p>
                    <p className={`text-sm ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-600'}`}>🚗 {driver.vehicleType || 'N/A'}</p>
                    <div className="flex items-center space-x-2 mt-1">
                      <span className={`w-2 h-2 rounded-full ${formData.isOnline ? 'bg-green-500' : 'bg-red-500'}`}></span>
                      <span className={`text-xs ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-500'}`}>{formData.isOnline ? '🟢 Available' : '🔴 Offline'}</span>
                    </div>
                  </div>
                </div>
                <p className={`text-xs ${userBackground === 'dark' ? 'text-blue-300' : 'text-blue-600'} mt-2`}>💡 This is how your profile appears to clients when they request fuel</p>
              </div>
            )}

            <div className={`p-4 rounded-lg border-2 ${hasExistingPassword ? userBackground === 'dark' ? 'bg-yellow-900/30 border-yellow-700' : 'bg-yellow-50 border-yellow-200' : userBackground === 'dark' ? 'bg-red-900/30 border-red-700' : 'bg-red-50 border-red-200'}`}>
              <div className="flex items-center justify-between">
                <div>
                  <h3 className={`text-sm font-bold ${hasExistingPassword ? userBackground === 'dark' ? 'text-yellow-400' : 'text-yellow-800' : userBackground === 'dark' ? 'text-red-400' : 'text-red-800'}`}>
                    {hasExistingPassword ? '🔑 Change Password' : '🔐 CREATE ACCOUNT'}
                  </h3>
                  <p className={`text-xs ${hasExistingPassword ? userBackground === 'dark' ? 'text-yellow-300' : 'text-yellow-700' : userBackground === 'dark' ? 'text-red-300' : 'text-red-700'}`}>
                    {hasExistingPassword ? 'Update the password for this driver' : 'Create a driver account with UID as document ID'}
                  </p>
                </div>
                <button type="button" onClick={() => setShowPasswordModal(true)} className={`px-4 py-2 text-sm font-bold rounded-lg transition ${hasExistingPassword ? 'bg-yellow-500 text-white hover:bg-yellow-600' : 'bg-red-500 text-white hover:bg-red-600 animate-pulse'}`}>
                  {hasExistingPassword ? 'Change Password' : 'CREATE ACCOUNT'}
                </button>
              </div>
            </div>

            <div className="flex items-center space-x-3">
              <input type="checkbox" name="isOnline" id="isOnline" checked={formData.isOnline} onChange={handleChange} className="w-4 h-4 text-green-600 border-gray-300 rounded focus:ring-green-500" />
              <label className={`text-sm ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'}`}>Driver is online and available</label>
            </div>

            <div className="flex items-center space-x-3">
              <input type="checkbox" name="isApproved" id="isApproved" checked={formData.isApproved} onChange={handleChange} className="w-4 h-4 text-green-600 border-gray-300 rounded focus:ring-green-500" />
              <label className={`text-sm ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'}`}>Driver is approved</label>
            </div>

            <div className="flex justify-between items-center pt-6 border-t border-gray-200">
              <button type="button" onClick={() => setShowDeleteModal(true)} className="px-4 py-2 text-sm font-medium text-white bg-red-500 rounded-lg hover:bg-red-600 transition">🗑️ Delete Driver</button>
              <div className="flex space-x-3">
                <Link href="/drivers" className={`px-4 py-2 text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300 bg-gray-700 hover:bg-gray-600' : 'text-gray-700 bg-gray-100 hover:bg-gray-200'} rounded-lg transition`}>Cancel</Link>
                <button type="submit" disabled={saving || emailError} className={`px-6 py-2 text-sm font-medium text-white rounded-lg transition ${emailError ? 'bg-gray-400 cursor-not-allowed' : 'bg-green-500 hover:bg-green-600'}`}>
                  {saving ? 'Saving...' : 'Update Driver'}
                </button>
              </div>
            </div>
          </form>
        </div>

        {/* Password Modal */}
        {showPasswordModal && (
          <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
            <div className={`rounded-lg shadow-xl max-w-md w-full p-6 mx-4 ${getCardClass()}`}>
              <div className="flex justify-between items-center mb-4">
                <h2 className={`text-xl font-bold ${hasExistingPassword ? 'text-yellow-700' : 'text-red-700'}`}>
                  {hasExistingPassword ? 'Change Password' : 'CREATE DRIVER ACCOUNT'}
                </h2>
                <button type="button" onClick={() => setShowPasswordModal(false)} className="text-gray-400 hover:text-gray-600">
                  <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </button>
              </div>
              
              <div className={`mb-4 p-3 rounded-md border ${hasExistingPassword ? 'bg-yellow-50 border-yellow-200' : 'bg-green-50 border-green-200'}`}>
                <p className={`text-sm ${hasExistingPassword ? 'text-yellow-700' : 'text-green-700'}`}>
                  <strong>Note:</strong> {hasExistingPassword ? 'This will update the driver\'s password in Firebase Auth.' : 'This will create a driver account with UID as document ID.'}
                </p>
                <div className="text-sm text-gray-600 mt-2 space-y-1">
                  <p>📧 Email: <strong>{driver?.email}</strong></p>
                  <p>👤 Name: <strong>{driver?.name}</strong></p>
                  <p>📱 Phone: <strong>{driver?.phone}</strong></p>
                </div>
                <div className="mt-2 p-2 bg-green-100 border border-green-300 rounded text-xs text-green-800">
                  ✅ <strong>Direct Update:</strong> Password will be updated directly in Firebase Auth.
                </div>
              </div>

              <form onSubmit={handleUpdatePassword} className="space-y-4">
                <div>
                  <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-2`}>New Password *</label>
                  <input type="password" name="newPassword" value={passwordData.newPassword} onChange={handlePasswordChange} required minLength={6} className={`w-full px-4 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500 ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'}`} placeholder="Enter new password (min 6 characters)" />
                </div>
                <div>
                  <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-2`}>Confirm New Password *</label>
                  <input type="password" name="confirmPassword" value={passwordData.confirmPassword} onChange={handlePasswordChange} required className={`w-full px-4 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500 ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'}`} placeholder="Confirm new password" />
                  {passwordData.newPassword && passwordData.confirmPassword && 
                   passwordData.newPassword !== passwordData.confirmPassword && (
                    <p className="text-xs text-red-500 mt-1">⚠️ Passwords do not match</p>
                  )}
                </div>
                <div className="flex justify-end space-x-3 pt-4">
                  <button type="button" onClick={() => { setShowPasswordModal(false); setPasswordData({ newPassword: '', confirmPassword: '' }); }} className={`px-4 py-2 text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300 bg-gray-700 hover:bg-gray-600' : 'text-gray-700 bg-gray-100 hover:bg-gray-200'} rounded-lg transition`}>Cancel</button>
                  <button type="submit" disabled={updatingPassword} className={`px-6 py-2 text-sm font-bold text-white rounded-lg transition disabled:opacity-50 ${hasExistingPassword ? 'bg-yellow-500 hover:bg-yellow-600' : 'bg-green-500 hover:bg-green-600 animate-pulse'}`}>
                    {updatingPassword ? (
                      <span className="flex items-center space-x-2">
                        <svg className="animate-spin h-4 w-4 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                          <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                          <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                        </svg>
                        <span>Updating...</span>
                      </span>
                    ) : (
                      hasExistingPassword ? 'Update Password' : 'CREATE ACCOUNT'
                    )}
                  </button>
                </div>
              </form>
            </div>
          </div>
        )}

        {/* Fuel Modal */}
        {showFuelModal && (
          <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
            <div className={`rounded-lg shadow-xl max-w-md w-full p-6 mx-4 ${getCardClass()}`}>
              <div className="flex justify-between items-center mb-4">
                <h2 className="text-xl font-bold text-gray-900"> Top Up Driver Fuel</h2>
                <button type="button" onClick={() => setShowFuelModal(false)} className="text-gray-400 hover:text-gray-600">
                  <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </button>
              </div>

              <div className="mb-4 p-3 bg-green-50 border border-green-200 rounded-md">
                <p className="text-sm text-green-700"><strong>Current Driver Fuel:</strong></p>
                <div className="grid grid-cols-2 gap-2 mt-2">
                  {driver?.remainingFuel && Object.entries(driver.remainingFuel).map(([type, amount]) => (
                    <div key={type} className="text-xs">
                      <span className="font-medium">{type}:</span> {amount}L
                    </div>
                  ))}
                </div>
              </div>

              <form onSubmit={handleFuelTopUp} className="space-y-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Fuel Type *</label>
                  <select 
                    name="fuelType" 
                    value={fuelData.fuelType} 
                    onChange={handleFuelChange} 
                    className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500"
                  >
                    <option value="Petrol">Petrol</option>
                    <option value="Diesel">Diesel</option>
                    <option value="Kerosene">Kerosene</option>
                    <option value="V-Power">V-Power</option>
                  </select>
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    Amount (Litres) *
                    <span className="text-xs text-blue-600 ml-2">
                      (Max: {mainTankStock[fuelData.fuelType]?.toFixed(1) || 0}L available)
                    </span>
                  </label>
                  <input 
                    type="number" 
                    name="amount" 
                    value={fuelData.amount || ''} 
                    onChange={handleFuelChange} 
                    required 
                    min="1" 
                    step="0.1" 
                    max={mainTankStock[fuelData.fuelType] || 0}
                    className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500" 
                    placeholder="Enter amount in litres" 
                  />
                  {mainTankStock[fuelData.fuelType] === 0 && (
                    <p className="text-xs text-red-500 mt-1 font-bold animate-pulse">
                      ⛔ No fuel available in main tank for {fuelData.fuelType}. Please import fuel first.
                    </p>
                  )}
                  {fuelData.amount > 0 && mainTankStock[fuelData.fuelType] > 0 && fuelData.amount <= mainTankStock[fuelData.fuelType] && (
                    <p className="text-xs text-green-500 mt-1">
                      ✅ After top-up: {(mainTankStock[fuelData.fuelType] - fuelData.amount).toFixed(1)}L remaining in main tank
                    </p>
                  )}
                  {fuelData.amount > 0 && mainTankStock[fuelData.fuelType] > 0 && fuelData.amount > mainTankStock[fuelData.fuelType] && (
                    <p className="text-xs text-red-500 mt-1 font-bold">
                      ⚠️ Amount exceeds available fuel! Maximum: {mainTankStock[fuelData.fuelType]?.toFixed(1)}L
                    </p>
                  )}
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Note (Optional)</label>
                  <input type="text" name="note" value={fuelData.note} onChange={handleFuelChange} className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500" placeholder="e.g., Admin top-up" />
                </div>
                <div className="flex justify-end space-x-3 pt-4">
                  <button type="button" onClick={() => setShowFuelModal(false)} className="px-4 py-2 text-sm font-medium text-gray-700 bg-gray-100 rounded-lg hover:bg-gray-200 transition">Cancel</button>
                  <button 
                    type="submit" 
                    disabled={updatingFuel || !fuelData.amount || fuelData.amount > (mainTankStock[fuelData.fuelType] || 0) || mainTankStock[fuelData.fuelType] === 0} 
                    className={`px-6 py-2 text-sm font-bold text-white rounded-lg transition disabled:opacity-50 ${
                      fuelData.amount > (mainTankStock[fuelData.fuelType] || 0) || mainTankStock[fuelData.fuelType] === 0
                        ? 'bg-red-500 cursor-not-allowed' 
                        : 'bg-green-500 hover:bg-green-600'
                    }`}
                  >
                    {updatingFuel ? 'Adding...' : 'Add Fuel'}
                  </button>
                </div>
              </form>
            </div>
          </div>
        )}

        {/* Delete Modal */}
        {showDeleteModal && (
          <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
            <div className="bg-white rounded-lg shadow-xl max-w-md w-full p-6 mx-4">
              <div className="flex justify-between items-center mb-4">
                <h2 className="text-xl font-bold text-red-600">⚠️ Delete Driver</h2>
                <button type="button" onClick={() => setShowDeleteModal(false)} className="text-gray-400 hover:text-gray-600">
                  <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </button>
              </div>
              
              <div className="mb-4 p-3 bg-red-50 border border-red-200 rounded-md">
                <p className="text-sm text-red-700"><strong>⚠️ Warning:</strong> This action cannot be undone!</p>
                <p className="text-sm text-gray-600 mt-2">You are about to delete driver: <strong>{driver?.name}</strong></p>
                <p className="text-sm text-gray-600">Email: <strong>{driver?.email}</strong></p>
                <p className="text-sm text-red-600 mt-2">This will permanently delete:</p>
                <ul className="text-sm text-gray-600 list-disc list-inside ml-2">
                  <li>Driver's Firebase Authentication account</li>
                  <li>Driver's Firestore document</li>
                  <li>Driver's profile photo from Storage</li>
                  <li>All driver data and history</li>
                </ul>
              </div>

              <div className="flex justify-end space-x-3 pt-4">
                <button type="button" onClick={() => setShowDeleteModal(false)} className="px-4 py-2 text-sm font-medium text-gray-700 bg-gray-100 rounded-lg hover:bg-gray-200 transition">Cancel</button>
                <button type="button" onClick={handleDeleteDriver} disabled={deletingDriver} className="px-6 py-2 text-sm font-bold text-white bg-red-500 rounded-lg hover:bg-red-600 transition disabled:opacity-50">
                  {deletingDriver ? 'Deleting...' : 'Delete Driver'}
                </button>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}