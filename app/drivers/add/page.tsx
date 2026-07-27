'use client';

import { useState, useRef, useCallback, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { db, storage, auth } from '../../../lib/firebase';
import { collection, doc, setDoc, getDocs, query, where, updateDoc, limit, getDoc } from 'firebase/firestore';
import { ref, uploadBytesResumable, getDownloadURL } from 'firebase/storage';
import { createUserWithEmailAndPassword, updateProfile, fetchSignInMethodsForEmail } from 'firebase/auth';
import toast from 'react-hot-toast';

export default function AddDriver() {
  const router = useRouter();
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [loading, setLoading] = useState(false);
  const [uploadingPhoto, setUploadingPhoto] = useState(false);
  const [uploadProgress, setUploadProgress] = useState(0);
  const [photoPreview, setPhotoPreview] = useState<string | null>(null);
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [emailError, setEmailError] = useState(false);
  const [emailChecking, setEmailChecking] = useState(false);
  const [passwordError, setPasswordError] = useState(false);
  const [passwordMatchError, setPasswordMatchError] = useState(false);
  const [userBackground, setUserBackground] = useState<string>('white');
  const [authEmailExists, setAuthEmailExists] = useState(false);

  const [formData, setFormData] = useState({
    name: '',
    email: '',
    phone: '',
    license: '',
    vehicleType: '',
    numberPlate: '',
    isOnline: false,
    isAvailable: false,
    isApproved: true,
    status: 'available',
    lat: 0,
    lng: 0,
    heading: 0,
    speed: 0,
    pricePerKm: 0,
    totalRevenueToday: 0,
    totalFuelSoldToday: 0,
    rating: 0,
    activeOrderId: null,
    currentClientName: null,
    currentClientPhone: null,
    currentClientPhoto: null,
    currentClientLocation: null,
    orderAccepted: false,
    orderStartedAt: null,
    lastOrderTime: null,
    lastSaleAmount: 0,
    lastSaleDate: null,
    lastSaleFuelType: null,
    lastSaleLitres: 0,
    lastSaleTime: null,
    lastCompletedOrderAt: null,
    completedOrders: 0,
    totalOrders: 0,
    driverSince: new Date().toISOString(),
    lastOnlineTime: null,
    lastOfflineTime: null,
    lastUpdate: new Date().toISOString(),
    profileComplete: true,
    userType: 'driver',
    driverPhoto: null,
    photoURL: null,
    remainingFuel: {
      Petrol: 0,
      Diesel: 0,
      Kerosene: 0,
      'V-Power': 0
    },
    fuelHistory: [],
    salesHistory: [],
    onlineHistory: [],
    offlineHistory: [],
    hasPasswordSet: true,
    authUserId: null,
    passwordUpdatedAt: new Date().toISOString(),
    emailVerified: false,
    password: '',
    confirmPassword: ''
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

  // Format phone number (matching Flutter)
  const formatPhoneNumber = (phone: string): string => {
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

  // Check if email already exists in Firebase Authentication
  const checkAuthEmailExists = useCallback(async (email: string) => {
    if (!email || email.trim() === '') return false;

    const emailTrimmed = email.trim();

    // Simple regex validation for email format
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(emailTrimmed)) {
      return false; // Invalid email format; don't call Firebase yet
    }

    try {
      const methods = await fetchSignInMethodsForEmail(auth, emailTrimmed);
      return methods.length > 0;
    } catch (error) {
      console.error('Error checking auth email:', error);
      return false;
    }
  }, []);

  // Check if email already exists in drivers collection
  const checkEmailExists = useCallback(async (email: string) => {
    if (!email || email.trim() === '') return false;

    setEmailChecking(true);
    try {
      // Check Firestore first
      const driversRef = collection(db, 'drivers');
      const q = query(driversRef, where('email', '==', email.trim()), limit(1));
      const querySnapshot = await getDocs(q);
      const firestoreExists = !querySnapshot.empty;

      // Also check Firebase Auth
      const authExists = await checkAuthEmailExists(email);

      const exists = firestoreExists || authExists;
      setAuthEmailExists(authExists);

      return exists;
    } catch (error) {
      console.error('Error checking email:', error);
      return false;
    } finally {
      setEmailChecking(false);
    }
  }, [checkAuthEmailExists]);

  const handleChange = useCallback((e) => {
    const { name, value, type } = e.target;
    const newValue = type === 'checkbox' ? e.target.checked : value;

    setFormData(prev => ({
      ...prev,
      [name]: newValue
    }));

    // Debounced email check
    if (name === 'email' && value) {
      clearTimeout((window as any).emailTimeout);
      (window as any).emailTimeout = setTimeout(async () => {
        const exists = await checkEmailExists(value);
        setEmailError(exists);
        if (exists) {
          toast.error('⚠️ This email is already used by another driver!');
        }
      }, 500);
    }

    // Password validation
    if (name === 'password' && value) {
      if (value.length < 6) {
        setPasswordError(true);
      } else {
        setPasswordError(false);
      }
      if (formData.confirmPassword && value !== formData.confirmPassword) {
        setPasswordMatchError(true);
      } else if (formData.confirmPassword && value === formData.confirmPassword) {
        setPasswordMatchError(false);
      }
    }

    if (name === 'confirmPassword' && value) {
      if (value !== formData.password) {
        setPasswordMatchError(true);
      } else {
        setPasswordMatchError(false);
      }
    }
  }, [formData.password, formData.confirmPassword, checkEmailExists]);

  const handleFuelChange = useCallback((fuelType, value) => {
    let cleanValue = value;
    if (cleanValue.startsWith('0') && cleanValue.length > 1) {
      cleanValue = cleanValue.replace(/^0+/, '');
    }
    setFormData(prev => ({
      ...prev,
      remainingFuel: {
        ...prev.remainingFuel,
        [fuelType]: cleanValue === '' ? 0 : parseFloat(cleanValue) || 0
      }
    }));
  }, []);

  const handleFuelBlur = useCallback((fuelType, value) => {
    const numValue = parseFloat(value) || 0;
    setFormData(prev => ({
      ...prev,
      remainingFuel: {
        ...prev.remainingFuel,
        [fuelType]: numValue
      }
    }));
  }, []);

  // ========== PHOTO SELECTION ==========
  const handleFileSelect = useCallback((e) => {
    const file = e.target.files?.[0];
    if (!file) {
      toast.error('No file selected');
      return;
    }

    if (!file.type.startsWith('image/')) {
      toast.error('Please select an image file (JPEG, PNG, etc.)');
      return;
    }

    if (file.size > 5 * 1024 * 1024) {
      toast.error('Image must be less than 5MB');
      return;
    }

    setSelectedFile(file);
    setUploadProgress(0);

    const reader = new FileReader();
    reader.onload = (event) => {
      setPhotoPreview(event.target?.result as string);
      toast.success('Photo selected! Ready to upload.');
    };
    reader.onerror = () => {
      toast.error('Failed to read file');
    };
    reader.readAsDataURL(file);
  }, []);

  // ========== UPLOAD PHOTO TO STORAGE ==========
  const uploadDriverPhoto = useCallback(async (driverId: string): Promise<string | null> => {
    if (!selectedFile) return null;

    return new Promise((resolve, reject) => {
      const storageRef = ref(storage, `drivers/${driverId}/profile`);
      const uploadTask = uploadBytesResumable(storageRef, selectedFile, {
        contentType: selectedFile.type
      });

      uploadTask.on(
        'state_changed',
        (snapshot) => {
          const progress = (snapshot.bytesTransferred / snapshot.totalBytes) * 100;
          setUploadProgress(Math.round(progress));
        },
        (error) => {
          console.error('❌ Upload error:', error);
          reject(error);
        },
        async () => {
          try {
            const downloadURL = await getDownloadURL(uploadTask.snapshot.ref);
            resolve(downloadURL);
          } catch (error) {
            reject(error);
          }
        }
      );
    });
  }, [selectedFile]);

  // ========== CREATE FIREBASE AUTH ACCOUNT ==========
  const createDriverAuthAccount = useCallback(async (email: string, password: string, name: string) => {
    try {
      // Double check if email exists in Auth before creating
      const authExists = await checkAuthEmailExists(email);
      if (authExists) {
        toast.error('⚠️ This email is already registered in Firebase Auth. Please use a different email.', {
          duration: 5000,
          icon: '🚫'
        });
        return { success: false, error: 'Email already in use', code: 'auth/email-already-in-use' };
      }

      const userCredential = await createUserWithEmailAndPassword(auth, email, password);
      const user = userCredential.user;

      await updateProfile(user, {
        displayName: name
      });

      console.log('✅ Auth account created for:', email);
      return { success: true, uid: user.uid, user: user };

    } catch (authError: any) {
      console.error('❌ Auth error:', authError);

      if (authError.code === 'auth/email-already-in-use') {
        toast.error('⚠️ This email is already registered. Please use a different email.', {
          duration: 5000,
          icon: '🚫'
        });
        return { success: false, error: 'Email already in use', code: authError.code };
      } else if (authError.code === 'auth/weak-password') {
        toast.error('⚠️ Password too weak. Use at least 6 characters.', {
          duration: 4000,
          icon: '⚠️'
        });
        return { success: false, error: 'Weak password' };
      } else {
        throw authError;
      }
    }
  }, [checkAuthEmailExists]);

  // ========== SUBMIT FORM - ADDS TO FIRESTORE WITH AUTH UID ==========
  const handleSubmit = useCallback(async (e) => {
    e.preventDefault();

    // Validate required fields
    if (!formData.name || !formData.email || !formData.phone) {
      toast.error('Please fill in all required fields (Name, Email, Phone)');
      return;
    }

    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(formData.email)) {
      toast.error('Please enter a valid email address');
      return;
    }

    // Validate password
    if (!formData.password || formData.password.length < 6) {
      toast.error('Password must be at least 6 characters');
      return;
    }

    if (formData.password !== formData.confirmPassword) {
      toast.error('Passwords do not match');
      return;
    }

    // Check if email already exists (Firestore + Auth)
    const emailExists = await checkEmailExists(formData.email);
    if (emailExists) {
      toast.error('⚠️ This email is already used by another driver!');
      setEmailError(true);
      return;
    }

    setLoading(true);

    try {
      // STEP 1: Create Firebase Auth Account with the provided password
      const authResult = await createDriverAuthAccount(
        formData.email,
        formData.password,
        formData.name
      );

      if (!authResult.success) {
        setLoading(false);
        return;
      }

      const authUid = authResult.uid;
      const formattedPhone = formatPhoneNumber(formData.phone);

      const now = new Date().toISOString();

      // ============================================================
      // COMPLETE DRIVER DOCUMENT WITH AUTH UID AS DOCUMENT ID
      // ============================================================
      const driverData = {
        // ============================================================
        // BASIC INFO
        // ============================================================
        userId: authUid,
        name: formData.name,
        phone: formattedPhone,
        email: formData.email,
        userType: 'driver',

        // ============================================================
        // VEHICLE INFO
        // ============================================================
        vehicleType: formData.vehicleType || 'Pending Assignment',
        numberPlate: formData.numberPlate || 'Pending Assignment',
        pricePerKm: parseFloat(formData.pricePerKm) || 0,
        license: formData.license || '',

        // ============================================================
        // STATUS & APPROVAL
        // ============================================================
        isApproved: true,
        isOnline: formData.isOnline || false,
        isAvailable: formData.isAvailable || false,
        status: formData.status || 'offline',
        orderAccepted: false,

        // ============================================================
        // LOCATION & SPEED
        // ============================================================
        lat: parseFloat(formData.lat) || 0.0,
        lng: parseFloat(formData.lng) || 0.0,
        latitude: parseFloat(formData.lat) || 0.0,
        longitude: parseFloat(formData.lng) || 0.0,
        heading: parseFloat(formData.heading) || 0.0,
        speed: parseFloat(formData.speed) || 0.0,

        // ============================================================
        // ORDER TRACKING
        // ============================================================
        activeOrderId: null,
        orderStartedAt: null,
        currentClientName: null,
        currentClientPhone: null,
        currentClientLocation: null,
        currentClientPhoto: null,

        // ============================================================
        // FUEL MANAGEMENT
        // ============================================================
        remainingFuel: {
          Petrol: parseFloat(formData.remainingFuel.Petrol) || 0.0,
          Diesel: parseFloat(formData.remainingFuel.Diesel) || 0.0,
          Kerosene: parseFloat(formData.remainingFuel.Kerosene) || 0.0,
          'V-Power': parseFloat(formData.remainingFuel['V-Power']) || 0.0,
        },
        fuelUpdatedAt: now,
        fuelHistory: [],

        // ============================================================
        // SALES & REVENUE
        // ============================================================
        salesHistory: [],
        totalFuelSoldToday: parseFloat(formData.totalFuelSoldToday) || 0.0,
        totalRevenueToday: parseFloat(formData.totalRevenueToday) || 0.0,
        lastSaleDate: null,
        lastSaleFuelType: null,
        lastSaleLitres: 0.0,
        lastSaleAmount: 0.0,
        lastSaleTime: null,
        lastOrderTime: null,

        // ============================================================
        // ORDER STATISTICS
        // ============================================================
        totalOrders: parseInt(formData.totalOrders) || 0,
        completedOrders: parseInt(formData.completedOrders) || 0,
        lastCompletedOrderAt: null,

        // ============================================================
        // ONLINE/OFFLINE HISTORY
        // ============================================================
        onlineHistory: [],
        offlineHistory: [],
        lastOnlineTime: formData.isOnline ? now : null,
        lastOfflineTime: !formData.isOnline ? now : null,
        lastUpdate: now,

        // ============================================================
        // PROFILE & METADATA
        // ============================================================
        profileComplete: true,
        driverPhoto: null,
        photoURL: null,
        rating: parseFloat(formData.rating) || 0.0,
        driverSince: now,
        createdAt: now,
        updatedAt: now,

        // ============================================================
        // AUTHENTICATION - Password stored in Auth, not Firestore
        // ============================================================
        hasPasswordSet: true,
        authUserId: authUid,
        passwordUpdatedAt: now,
        emailVerified: false
      };

      // STEP: Create driver document with AUTH UID as document ID (Matching Flutter)
      const driverRef = doc(db, 'drivers', authUid);
      await setDoc(driverRef, driverData);

      console.log('✅ Driver created with Auth UID:', authUid);

      // STEP: Upload photo if selected
      if (selectedFile) {
        setUploadingPhoto(true);
        try {
          const photoURL = await uploadDriverPhoto(authUid);
          if (photoURL) {
            await updateDoc(driverRef, {
              photoURL: photoURL,
              driverPhoto: photoURL
            });
            console.log('✅ Photo URL saved to Firestore');
          }
        } catch (uploadError) {
          console.error('❌ Photo upload failed:', uploadError);
          toast.error('Photo upload failed, but driver was created.');
        } finally {
          setUploadingPhoto(false);
          setUploadProgress(0);
        }
      }

      // Show success messages
      toast.success(`✅ Driver "${formData.name}" added successfully!`, {
        duration: 5000,
        icon: '🎉'
      });

      toast(`📋 Auth UID: ${authUid}`, {
        duration: 4000,
        icon: '🆔'
      });

      toast(`🔐 Password set successfully!`, {
        duration: 4000,
        icon: '🔑'
      });

      // Redirect
      setTimeout(() => {
        router.push('/drivers');
      }, 3000);

    } catch (error: any) {
      console.error('❌ Error adding driver:', error);

      if (error.code === 'auth/email-already-in-use') {
        toast.error('⚠️ This email is already registered. Please use a different email.', {
          duration: 5000,
          icon: '🚫'
        });
      } else {
        toast.error('Failed to add driver: ' + (error.message || 'Unknown error'));
      }
    } finally {
      setLoading(false);
    }
  }, [formData, checkEmailExists, createDriverAuthAccount, uploadDriverPhoto, selectedFile, router]);

  // Get background class based on user preference - FULL SCREEN COVERAGE
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
        return 'bg-gray-800/95 text-white border-gray-700';
      case 'skyblue':
        return 'bg-white/90 backdrop-blur-sm shadow-lg';
      case 'gray':
        return 'bg-white shadow-lg';
      default:
        return 'bg-white shadow-lg';
    }
  };

  return (
    <div className={`min-h-screen w-full p-4 md:p-6 transition-colors duration-300 ${getBackgroundClass()}`}>
      <div className="max-w-9xl mx-auto">
        <div className={`rounded-lg p-4 md:p-6 transition-colors duration-300 ${getCardClass()}`}>
          <div className="flex items-center justify-between mb-6">
            <div>
              <h1 className="text-2xl font-bold">Add New Driver</h1>
              <p className={`text-sm mt-1 ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>
                Create a new driver account with complete details
              </p>
            </div>
            <Link
              href="/drivers"
              className={`text-sm ${userBackground === 'dark' ? 'text-gray-400 hover:text-gray-200' : 'text-gray-500 hover:text-gray-700'} flex items-center space-x-1`}
            >
              <span>←</span>
              <span>Back to Drivers</span>
            </Link>
          </div>

          <form onSubmit={handleSubmit} className="space-y-6">
            {/* Profile Photo Section */}
            <div className={`border-b ${userBackground === 'dark' ? 'border-gray-700' : 'border-gray-200'} pb-6`}>
              <h3 className={`text-lg font-semibold ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'} mb-4`}>Profile Photo</h3>
              <div className="flex flex-col items-center space-y-4">
                <div className="relative">
                  <div className={`w-32 h-32 rounded-full overflow-hidden ${userBackground === 'dark' ? 'bg-gray-700' : 'bg-gray-100'} border-2 ${userBackground === 'dark' ? 'border-gray-600' : 'border-gray-200'}`}>
                    {photoPreview ? (
                      <img
                        src={photoPreview}
                        alt="Driver profile preview"
                        className="w-full h-full object-cover"
                      />
                    ) : (
                      <div className={`w-full h-full flex items-center justify-center ${userBackground === 'dark' ? 'bg-gray-700' : 'bg-gray-100'}`}>
                        <span className={`text-4xl ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-400'}`}>
                          {formData.name?.charAt(0)?.toUpperCase() || '?'}
                        </span>
                      </div>
                    )}
                  </div>
                  {(uploadingPhoto || (loading && selectedFile)) && (
                    <div className="absolute inset-0 bg-black bg-opacity-50 rounded-full flex items-center justify-center">
                      <div className="flex flex-col items-center">
                        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-white"></div>
                        <span className="text-white text-xs mt-1">{uploadProgress}%</span>
                      </div>
                    </div>
                  )}
                </div>

                <div className="flex flex-wrap gap-3 justify-center">
                  <input
                    type="file"
                    ref={fileInputRef}
                    onChange={handleFileSelect}
                    accept="image/jpeg,image/png,image/gif,image/webp"
                    className="hidden"
                  />
                  <button
                    type="button"
                    onClick={() => fileInputRef.current?.click()}
                    disabled={uploadingPhoto || loading}
                    className="px-4 py-2 text-sm font-medium text-white bg-blue-500 rounded-lg hover:bg-blue-600 transition disabled:opacity-50"
                  >
                    📁 Select Photo
                  </button>
                  {selectedFile && !uploadingPhoto && !loading && (
                    <button
                      type="button"
                      onClick={() => {
                        setSelectedFile(null);
                        setPhotoPreview(null);
                        if (fileInputRef.current) {
                          fileInputRef.current.value = '';
                        }
                      }}
                      className="px-4 py-2 text-sm font-medium text-gray-700 bg-gray-100 rounded-lg hover:bg-gray-200 transition"
                    >
                      ✖ Remove Selection
                    </button>
                  )}
                </div>
                {selectedFile && (
                  <p className="text-xs text-green-600">
                    📄 {selectedFile.name} ({(selectedFile.size / 1024).toFixed(1)} KB) - Will be uploaded when you save
                  </p>
                )}
                <p className={`text-xs ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>Max 5MB (JPEG, PNG, GIF, WebP)</p>
              </div>
            </div>

            {/* Basic Information */}
            <div className={`border-b ${userBackground === 'dark' ? 'border-gray-700' : 'border-gray-200'} pb-6`}>
              <h3 className={`text-lg font-semibold ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'} mb-4`}>Basic Information</h3>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4 md:gap-6">
                <div>
                  <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-2`}>
                    Full Name *
                  </label>
                  <input
                    type="text"
                    name="name"
                    required
                    className={`w-full px-4 py-2 border ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'} rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500`}
                    placeholder="John Doe"
                    value={formData.name}
                    onChange={handleChange}
                  />
                </div>

                <div>
                  <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-2`}>
                    Email *
                  </label>
                  <input
                    type="email"
                    name="email"
                    required
                    className={`w-full px-4 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500 ${emailError ? 'border-red-500 bg-red-50' : userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'
                      }`}
                    placeholder="john@example.com"
                    value={formData.email}
                    onChange={handleChange}
                  />
                  {emailChecking && (
                    <p className="text-xs text-blue-500 mt-1">Checking email...</p>
                  )}
                  {emailError && (
                    <p className="text-xs text-red-500 mt-1">⚠️ This email is already used by another driver!</p>
                  )}
                  {authEmailExists && (
                    <p className="text-xs text-red-500 mt-1">⚠️ This email is already registered in Firebase Auth!</p>
                  )}
                </div>

                <div>
                  <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-2`}>
                    Phone Number *
                  </label>
                  <input
                    type="tel"
                    name="phone"
                    required
                    className={`w-full px-4 py-2 border ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'} rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500`}
                    placeholder="0712345678"
                    value={formData.phone}
                    onChange={handleChange}
                  />
                </div>

                <div>
                  <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-2`}>
                    License Number
                  </label>
                  <input
                    type="text"
                    name="license"
                    className={`w-full px-4 py-2 border ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'} rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500`}
                    placeholder="DL-123456"
                    value={formData.license}
                    onChange={handleChange}
                  />
                </div>

                <div>
                  <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-2`}>
                    Vehicle Type
                  </label>
                  <input
                    type="text"
                    name="vehicleType"
                    className={`w-full px-4 py-2 border ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'} rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500`}
                    placeholder="Truck, Van, Car"
                    value={formData.vehicleType}
                    onChange={handleChange}
                  />
                </div>

                <div>
                  <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-2`}>
                    Number Plate
                  </label>
                  <input
                    type="text"
                    name="numberPlate"
                    className={`w-full px-4 py-2 border ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'} rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500`}
                    placeholder="KCA 123A"
                    value={formData.numberPlate}
                    onChange={handleChange}
                  />
                </div>

                <div>
                  <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-2`}>
                    Price Per KM (KES)
                  </label>
                  <input
                    type="number"
                    name="pricePerKm"
                    className={`w-full px-4 py-2 border ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'} rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500`}
                    placeholder="0"
                    value={formData.pricePerKm}
                    onChange={handleChange}
                    step="0.01"
                  />
                </div>
              </div>
            </div>

            {/* Password Section */}
            <div className={`border-b ${userBackground === 'dark' ? 'border-gray-700' : 'border-gray-200'} pb-6`}>
              <h3 className={`text-lg font-semibold ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'} mb-4`}>🔐 Set Password</h3>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4 md:gap-6">
                <div>
                  <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-2`}>
                    Password *
                  </label>
                  <input
                    type="password"
                    name="password"
                    required
                    className={`w-full px-4 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500 ${passwordError ? 'border-red-500 bg-red-50' : userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'
                      }`}
                    placeholder="Enter password (min 6 characters)"
                    value={formData.password}
                    onChange={handleChange}
                  />
                  {passwordError && (
                    <p className="text-xs text-red-500 mt-1">⚠️ Password must be at least 6 characters</p>
                  )}
                  {!passwordError && formData.password && (
                    <p className="text-xs text-green-500 mt-1">✅ Password strength: Good</p>
                  )}
                </div>

                <div>
                  <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-2`}>
                    Confirm Password *
                  </label>
                  <input
                    type="password"
                    name="confirmPassword"
                    required
                    className={`w-full px-4 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500 ${passwordMatchError ? 'border-red-500 bg-red-50' : userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'
                      }`}
                    placeholder="Confirm password"
                    value={formData.confirmPassword}
                    onChange={handleChange}
                  />
                  {passwordMatchError && (
                    <p className="text-xs text-red-500 mt-1">⚠️ Passwords do not match</p>
                  )}
                  {!passwordMatchError && formData.confirmPassword && formData.password === formData.confirmPassword && (
                    <p className="text-xs text-green-500 mt-1">✅ Passwords match</p>
                  )}
                </div>
              </div>
            </div>

            {/* Initial Fuel Stock */}
            <div className={`border-b ${userBackground === 'dark' ? 'border-gray-700' : 'border-gray-200'} pb-6`}>
              <h3 className={`text-lg font-semibold ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'} mb-4`}>Initial Fuel Stock</h3>
              <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                {['Petrol', 'Diesel', 'Kerosene', 'V-Power'].map((fuelType) => (
                  <div key={fuelType}>
                    <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-2`}>
                      {fuelType} (Litres)
                    </label>
                    <input
                      type="number"
                      className={`w-full px-4 py-2 border ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'} rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500`}
                      placeholder="0"
                      value={formData.remainingFuel[fuelType] || ''}
                      onChange={(e) => handleFuelChange(fuelType, e.target.value)}
                      onBlur={(e) => handleFuelBlur(fuelType, e.target.value)}
                      step="0.01"
                      min="0"
                    />
                  </div>
                ))}
              </div>
            </div>

            {/* Status & Availability */}
            <div className={`border-b ${userBackground === 'dark' ? 'border-gray-700' : 'border-gray-200'} pb-6`}>
              <h3 className={`text-lg font-semibold ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'} mb-4`}>Status & Availability</h3>
              <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div className="flex items-center space-x-3 pt-2">
                  <input
                    type="checkbox"
                    name="isOnline"
                    className="w-4 h-4 text-green-600 border-gray-300 rounded focus:ring-green-500"
                    checked={formData.isOnline}
                    onChange={handleChange}
                  />
                  <label className={`text-sm ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'}`}>Driver is Online</label>
                </div>

                <div className="flex items-center space-x-3 pt-2">
                  <input
                    type="checkbox"
                    name="isAvailable"
                    className="w-4 h-4 text-green-600 border-gray-300 rounded focus:ring-green-500"
                    checked={formData.isAvailable}
                    onChange={handleChange}
                  />
                  <label className={`text-sm ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'}`}>Driver is Available</label>
                </div>

                <div>
                  <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-2`}>
                    Status
                  </label>
                  <select
                    name="status"
                    value={formData.status}
                    onChange={handleChange}
                    className={`w-full px-4 py-2 border ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'} rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500`}
                  >
                    <option value="available">Available</option>
                    <option value="busy">Busy</option>
                    <option value="offline">Offline</option>
                    <option value="on_break">On Break</option>
                  </select>
                </div>
              </div>
            </div>

            {/* Initial Location */}
            <div className={`border-b ${userBackground === 'dark' ? 'border-gray-700' : 'border-gray-200'} pb-6`}>
              <h3 className={`text-lg font-semibold ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'} mb-4`}>Initial Location</h3>
              <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div>
                  <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-2`}>
                    Latitude
                  </label>
                  <input
                    type="number"
                    name="lat"
                    className={`w-full px-4 py-2 border ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'} rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500`}
                    placeholder="0"
                    value={formData.lat}
                    onChange={handleChange}
                    step="0.0000001"
                  />
                </div>

                <div>
                  <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-2`}>
                    Longitude
                  </label>
                  <input
                    type="number"
                    name="lng"
                    className={`w-full px-4 py-2 border ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'} rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500`}
                    placeholder="0"
                    value={formData.lng}
                    onChange={handleChange}
                    step="0.0000001"
                  />
                </div>

                <div>
                  <label className={`block text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300' : 'text-gray-700'} mb-2`}>
                    Heading
                  </label>
                  <input
                    type="number"
                    name="heading"
                    className={`w-full px-4 py-2 border ${userBackground === 'dark' ? 'bg-gray-700 text-white border-gray-600' : 'bg-white border-gray-300'} rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500`}
                    placeholder="0"
                    value={formData.heading}
                    onChange={handleChange}
                    step="0.1"
                  />
                </div>
              </div>
            </div>

            {/* Info Box */}
            <div className="p-4 rounded-lg bg-cyan-500 border border-blue-700 text-white">
              <p className="text-sm">
                ℹ️ Driver will be created with:
                <br />
                • Db Auth account with the password you set
                <br />
                • Driver document in db with Auth UID as document ID
                <br />
                • Driver can login immediately with the password you provided
                <br />
                • <strong>Important:</strong> Password must be at least 6 characters
                <br />
                • <strong>Email check:</strong> Both db and system Auth are checked for existing emails
              </p>
            </div>

            {/* Action Buttons */}
            <div className="flex justify-end space-x-3 pt-6 border-t border-gray-200">
              <Link
                href="/drivers"
                className={`px-4 py-2 text-sm font-medium ${userBackground === 'dark' ? 'text-gray-300 bg-gray-700 hover:bg-gray-600' : 'text-gray-700 bg-gray-100 hover:bg-gray-200'} rounded-lg transition`}
              >
                Cancel
              </Link>
              <button
                type="submit"
                disabled={
                  loading ||
                  uploadingPhoto ||
                  emailError ||
                  emailChecking ||
                  passwordError ||
                  passwordMatchError ||
                  !formData.password ||
                  !formData.confirmPassword ||
                  authEmailExists
                }
                className={`px-6 py-2 text-sm font-medium text-white rounded-lg transition disabled:opacity-50 disabled:cursor-not-allowed ${emailError || passwordError || passwordMatchError || authEmailExists ? 'bg-gray-400' : 'bg-green-500 hover:bg-green-600'
                  }`}
              >
                {loading || uploadingPhoto ? (
                  <span className="flex items-center space-x-2">
                    <svg className="animate-spin h-4 w-4 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                      <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                      <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                    </svg>
                    <span>{uploadingPhoto ? 'Uploading Photo...' : 'Adding...'}</span>
                  </span>
                ) : (
                  'Add Driver'
                )}
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
  );
}