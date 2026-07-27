'use client';

import { useState, useEffect } from 'react';
import { auth, db } from '../../lib/firebase';
import { updatePassword, EmailAuthProvider, reauthenticateWithCredential, signOut } from 'firebase/auth';
import { doc, getDoc, setDoc, onSnapshot } from 'firebase/firestore';
import { useRouter } from 'next/navigation';
import toast from 'react-hot-toast';

// Generate a unique user ID
const generateUserId = (email: string) => {
  const emailPrefix = email.substring(0, 3).toUpperCase();
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  let randomPart = '';
  for (let i = 0; i < 6; i++) {
    randomPart += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  const timestamp = Date.now().toString();
  const timePart = timestamp.slice(-3);
  return `${emailPrefix}${randomPart}${timePart}`;
};

export default function Settings() {
  const [user, setUser] = useState<any>(null);
  const [loading, setLoading] = useState<boolean>(true);
  const [updating, setUpdating] = useState<boolean>(false);
  const [currentPassword, setCurrentPassword] = useState<string>('');
  const [newPassword, setNewPassword] = useState<string>('');
  const [confirmPassword, setConfirmPassword] = useState<string>('');
  const [error, setError] = useState<string>('');
  const [success, setSuccess] = useState<string>('');
  const [background, setBackground] = useState<string>('white');
  const [copied, setCopied] = useState<boolean>(false);
  const [displayUserId, setDisplayUserId] = useState<string>('');
  const [showLogoutConfirm, setShowLogoutConfirm] = useState<boolean>(false);
  const [loggingOut, setLoggingOut] = useState<boolean>(false);
  const [isBackgroundLoaded, setIsBackgroundLoaded] = useState<boolean>(false);
  const router = useRouter();

  const getBackgroundColor = (bg: string) => {
    switch (bg) {
      case 'dark': return '#111827';
      case 'skyblue': return '#93c5fd';
      case 'gray': return '#e5e7eb';
      default: return '#f3f4f6';
    }
  };

  // Listen for background changes from Firestore
  useEffect(() => {
    const currentUser = auth.currentUser;
    if (!currentUser) return;

    const userRef = doc(db, 'users', currentUser.uid);
    
    const unsubscribe = onSnapshot(
      userRef,
      (docSnap) => {
        if (docSnap.exists()) {
          const data = docSnap.data();
          if (data.background) {
            setBackground(data.background);
            document.documentElement.style.backgroundColor = getBackgroundColor(data.background);
          }
          setIsBackgroundLoaded(true);
        }
      },
      (error) => {
        console.error('Error listening to background changes:', error);
        setIsBackgroundLoaded(true);
      }
    );

    return () => unsubscribe();
  }, []);

  useEffect(() => {
    const fetchUserData = async () => {
      const currentUser = auth.currentUser;
      if (!currentUser) {
        router.push('/login');
        return;
      }

      try {
        const userDoc = await getDoc(doc(db, 'users', currentUser.uid));
        if (userDoc.exists()) {
          const userData = userDoc.data();
          
          let userId = userData.userId;
          if (!userId) {
            userId = generateUserId(currentUser.email || 'user');
            await setDoc(doc(db, 'users', currentUser.uid), {
              userId: userId,
              updatedAt: new Date().toISOString()
            }, { merge: true });
          }
          
          setUser({
            uid: currentUser.uid,
            email: currentUser.email,
            name: userData.name || 'User',
            role: userData.role || 'user',
            userId: userId
          });
          setDisplayUserId(userId);
          
          // Only set background from DB if it exists, otherwise keep default
          if (userData.background) {
            setBackground(userData.background);
            document.documentElement.style.backgroundColor = getBackgroundColor(userData.background);
          }
          setIsBackgroundLoaded(true);
        } else {
          const userId = generateUserId(currentUser.email || 'user');
          setUser({
            uid: currentUser.uid,
            email: currentUser.email,
            name: currentUser.displayName || 'User',
            role: 'user',
            userId: userId
          });
          setDisplayUserId(userId);
          setIsBackgroundLoaded(true);
        }
      } catch (error) {
        console.error('Error fetching user data:', error);
        toast.error('Failed to load user data');
        setIsBackgroundLoaded(true);
      } finally {
        setLoading(false);
      }
    };

    fetchUserData();
  }, [router]);

  const handlePasswordChange = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setSuccess('');
    setUpdating(true);

    const currentUser = auth.currentUser;
    if (!currentUser) {
      setError('No user logged in');
      setUpdating(false);
      return;
    }

    if (!currentPassword || !newPassword || !confirmPassword) {
      setError('Please fill in all password fields');
      setUpdating(false);
      return;
    }

    if (newPassword.length < 6) {
      setError('New password must be at least 6 characters');
      setUpdating(false);
      return;
    }

    if (newPassword !== confirmPassword) {
      setError('New passwords do not match');
      setUpdating(false);
      return;
    }

    if (currentPassword === newPassword) {
      setError('New password must be different from current password');
      setUpdating(false);
      return;
    }

    try {
      const credential = EmailAuthProvider.credential(
        currentUser.email!,
        currentPassword
      );
      
      await reauthenticateWithCredential(currentUser, credential);
      await updatePassword(currentUser, newPassword);
      
      const userRef = doc(db, 'users', currentUser.uid);
      await setDoc(userRef, {
        passwordUpdatedAt: new Date().toISOString(),
        hasPasswordSet: true,
        updatedAt: new Date().toISOString()
      }, { merge: true });

      setSuccess('Password updated successfully!');
      toast.success('✅ Password changed successfully!');
      
      setCurrentPassword('');
      setNewPassword('');
      setConfirmPassword('');
      
    } catch (error: any) {
      console.error('Password update error:', error);
      
      switch (error.code) {
        case 'auth/wrong-password':
          setError('Current password is incorrect');
          toast.error('❌ Wrong password');
          break;
        case 'auth/too-many-requests':
          setError('Too many attempts. Please try again later.');
          toast.error('⛔ Too many attempts');
          break;
        case 'auth/requires-recent-login':
          setError('Please log in again before changing your password');
          toast.error('⚠️ Please re-login');
          break;
        case 'auth/weak-password':
          setError('Password is too weak. Please use at least 6 characters with a mix of letters and numbers.');
          toast.error('❌ Weak password');
          break;
        default:
          setError('Failed to update password. Please try again.');
          toast.error('❌ Password update failed');
      }
    } finally {
      setUpdating(false);
    }
  };

  const handleBackgroundChange = async (color: string) => {
    // Only update if the color is different from current
    if (color === background) return;
    
    setBackground(color);
    document.documentElement.style.backgroundColor = getBackgroundColor(color);
    
    const currentUser = auth.currentUser;
    if (!currentUser) return;

    try {
      await setDoc(doc(db, 'users', currentUser.uid), {
        background: color,
        updatedAt: new Date().toISOString()
      }, { merge: true });
      
      toast.success('Background updated successfully! It will apply to all pages.');
    } catch (error) {
      console.error('Error updating background:', error);
      toast.error('Failed to update background');
      // Revert to previous background if update fails
      const userDoc = await getDoc(doc(db, 'users', currentUser.uid));
      if (userDoc.exists()) {
        const data = userDoc.data();
        if (data.background) {
          setBackground(data.background);
          document.documentElement.style.backgroundColor = getBackgroundColor(data.background);
        }
      }
    }
  };

  const handleLogout = async () => {
    setLoggingOut(true);
    try {
      await signOut(auth);
      toast.success('Logged out successfully');
      router.push('/login');
    } catch (error) {
      console.error('Logout error:', error);
      toast.error('Failed to logout. Please try again.');
    } finally {
      setLoggingOut(false);
      setShowLogoutConfirm(false);
    }
  };

  const copyToClipboard = (text: string) => {
    navigator.clipboard.writeText(text).then(() => {
      setCopied(true);
      toast.success('User ID copied to clipboard');
      setTimeout(() => setCopied(false), 3000);
    }).catch(() => {
      toast.error('Failed to copy');
    });
  };

  // Background classes
  const getBackgroundClass = () => {
    switch (background) {
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

  const getCardClass = () => {
    switch (background) {
      case 'dark':
        return 'bg-gray-800 text-white border-gray-700';
      case 'skyblue':
        return 'bg-white/80 backdrop-blur-sm';
      case 'gray':
        return 'bg-white shadow-lg';
      default:
        return 'bg-white shadow-lg';
    }
  };

  const getInputClass = () => {
    switch (background) {
      case 'dark':
        return 'bg-gray-700 text-white border-gray-600 focus:ring-blue-400';
      case 'skyblue':
        return 'bg-white/90 border-blue-200 focus:ring-blue-500';
      case 'gray':
        return 'bg-white border-gray-300 focus:ring-gray-500';
      default:
        return 'border-gray-300 focus:ring-green-500';
    }
  };

  if (loading || !isBackgroundLoaded) {
    return (
      <div className={`min-h-screen flex items-center justify-center ${getBackgroundClass()}`}>
        <div className="text-lg">Loading...</div>
      </div>
    );
  }

  return (
    <div className={`min-h-screen py-8 px-4 transition-colors duration-300 ${getBackgroundClass()}`}>
      <div className="max-w-3xl mx-auto">
        <div className={`rounded-lg p-8 transition-colors duration-300 ${getCardClass()}`}>
          <div className="flex items-center justify-between mb-8">
            <div>
              <h1 className="text-3xl font-bold">Settings</h1>
              <p className={`text-sm mt-1 ${background === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>
                Manage your account settings and preferences
              </p>
            </div>
            <div className={`w-12 h-12 rounded-full flex items-center justify-center ${background === 'dark' ? 'bg-gray-700' : 'bg-green-100'}`}>
              <span className={`text-xl font-semibold ${background === 'dark' ? 'text-white' : 'text-green-600'}`}>
                {user?.name?.charAt(0).toUpperCase() || 'U'}
              </span>
            </div>
          </div>

          {/* User Info */}
          <div className={`mb-8 p-4 rounded-lg ${background === 'dark' ? 'bg-gray-700' : 'bg-gray-50'}`}>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label className={`text-sm font-medium ${background === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>
                  Full Name
                </label>
                <p className={`text-lg font-semibold ${background === 'dark' ? 'text-white' : 'text-gray-800'}`}>
                  {user?.name || 'User'}
                </p>
              </div>
              <div>
                <label className={`text-sm font-medium ${background === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>
                  Email Address
                </label>
                <p className={`text-lg font-semibold ${background === 'dark' ? 'text-white' : 'text-gray-800'}`}>
                  {user?.email || 'No email'}
                </p>
              </div>
              <div>
                <label className={`text-sm font-medium ${background === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>
                  Role
                </label>
                <p className={`text-lg font-semibold ${background === 'dark' ? 'text-white' : 'text-gray-800'}`}>
                  {user?.role || 'User'}
                </p>
              </div>
              <div>
                <label className={`text-sm font-medium ${background === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>
                  User ID
                </label>
                <div className="flex items-center gap-2 mt-1">
                  <p className={`text-lg font-bold ${background === 'dark' ? 'text-blue-400' : 'text-blue-600'}`}>
                    {displayUserId || 'Not set'}
                  </p>
                  <button
                    onClick={() => copyToClipboard(displayUserId)}
                    className={`px-3 py-1 rounded transition text-sm flex-shrink-0 ${
                      copied 
                        ? 'bg-green-500 text-white' 
                        : background === 'dark' 
                          ? 'bg-gray-600 hover:bg-gray-500 text-white' 
                          : 'bg-blue-500 hover:bg-blue-600 text-white'
                    }`}
                    title="Copy User ID"
                  >
                    {copied ? '✓' : '📋'}
                  </button>
                </div>
              </div>
            </div>
          </div>

          {/* Change Password */}
          <div className={`mb-8 p-6 rounded-lg ${background === 'dark' ? 'bg-gray-700' : 'bg-gray-50'}`}>
            <h2 className={`text-xl font-bold mb-4 ${background === 'dark' ? 'text-white' : 'text-gray-800'}`}>
              Change Password
            </h2>
            
            <div className={`mb-4 p-3 rounded-md text-sm ${
              background === 'dark' 
                ? 'bg-blue-900/30 border border-blue-700 text-blue-200' 
                : 'bg-blue-50 border border-blue-200 text-blue-700'
            }`}>
              <strong>ℹ️ Note:</strong> Your password is securely stored in Db Authentication. 
              After changing it, you can use the new password to login on both web and Flutter.
            </div>

            {error && (
              <div className={`mb-4 p-3 rounded-md text-sm ${
                background === 'dark' 
                  ? 'bg-red-900/50 border-red-700 text-red-200' 
                  : 'bg-red-50 border border-red-400 text-red-700'
              }`}>
                <strong>Error:</strong> {error}
              </div>
            )}

            {success && (
              <div className={`mb-4 p-3 rounded-md text-sm ${
                background === 'dark'
                  ? 'bg-green-900/50 border-green-700 text-green-200'
                  : 'bg-green-50 border border-green-400 text-green-700'
              }`}>
                <strong>✅ Success:</strong> {success}
              </div>
            )}

            <form onSubmit={handlePasswordChange}>
              <div className="space-y-4">
                <div>
                  <label className={`block text-sm font-medium mb-2 ${background === 'dark' ? 'text-gray-300' : 'text-gray-700'}`}>
                    Current Password
                  </label>
                  <input
                    type="password"
                    value={currentPassword}
                    onChange={(e) => setCurrentPassword(e.target.value)}
                    placeholder="Enter your current password"
                    className={`w-full px-4 py-2 border rounded-md focus:outline-none focus:ring-2 transition-colors ${getInputClass()}`}
                    required
                  />
                </div>
                <div>
                  <label className={`block text-sm font-medium mb-2 ${background === 'dark' ? 'text-gray-300' : 'text-gray-700'}`}>
                    New Password
                  </label>
                  <input
                    type="password"
                    value={newPassword}
                    onChange={(e) => setNewPassword(e.target.value)}
                    placeholder="Enter new password (min 6 characters)"
                    className={`w-full px-4 py-2 border rounded-md focus:outline-none focus:ring-2 transition-colors ${getInputClass()}`}
                    required
                  />
                </div>
                <div>
                  <label className={`block text-sm font-medium mb-2 ${background === 'dark' ? 'text-gray-300' : 'text-gray-700'}`}>
                    Confirm New Password
                  </label>
                  <input
                    type="password"
                    value={confirmPassword}
                    onChange={(e) => setConfirmPassword(e.target.value)}
                    placeholder="Confirm your new password"
                    className={`w-full px-4 py-2 border rounded-md focus:outline-none focus:ring-2 transition-colors ${getInputClass()}`}
                    required
                  />
                </div>
                <button
                  type="submit"
                  disabled={updating}
                  className="w-full bg-blue-500 hover:bg-blue-600 text-white font-semibold py-3 px-4 rounded-md transition disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  {updating ? '🔄 Updating Password...' : '🔐 Update Password'}
                </button>
              </div>
            </form>
          </div>

          {/* Background Theme */}
          <div className={`p-6 rounded-lg ${background === 'dark' ? 'bg-gray-700' : 'bg-gray-50'}`}>
            <h2 className={`text-xl font-bold mb-4 ${background === 'dark' ? 'text-white' : 'text-gray-800'}`}>
              Theme Preferences
            </h2>
            <p className={`text-sm mb-4 ${background === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>
              Choose your preferred background color. This will apply to all pages.
            </p>
            
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              <button
                onClick={() => handleBackgroundChange('white')}
                className={`p-4 rounded-lg border-2 transition-all ${
                  background === 'white' 
                    ? 'border-blue-500 shadow-lg scale-105' 
                    : 'border-gray-200 hover:border-gray-300'
                } bg-white`}
              >
                <div className="w-full h-12 bg-gray-100 rounded-md mb-2"></div>
                <p className="text-sm font-medium text-gray-700">Light</p>
              </button>
              
              <button
                onClick={() => handleBackgroundChange('gray')}
                className={`p-4 rounded-lg border-2 transition-all ${
                  background === 'gray' 
                    ? 'border-blue-500 shadow-lg scale-105' 
                    : 'border-gray-200 hover:border-gray-300'
                } bg-gray-200`}
              >
                <div className="w-full h-12 bg-gray-300 rounded-md mb-2"></div>
                <p className="text-sm font-medium text-gray-700">Gray</p>
              </button>
              
              <button
                onClick={() => handleBackgroundChange('skyblue')}
                className={`p-4 rounded-lg border-2 transition-all ${
                  background === 'skyblue' 
                    ? 'border-blue-500 shadow-lg scale-105' 
                    : 'border-gray-200 hover:border-gray-300'
                } bg-gradient-to-br from-blue-100 to-blue-300`}
              >
                <div className="w-full h-12 bg-gradient-to-br from-blue-200 to-blue-400 rounded-md mb-2"></div>
                <p className="text-sm font-medium text-gray-700">Sky Blue</p>
              </button>
              
              <button
                onClick={() => handleBackgroundChange('dark')}
                className={`p-4 rounded-lg border-2 transition-all ${
                  background === 'dark' 
                    ? 'border-blue-500 shadow-lg scale-105' 
                    : 'border-gray-200 hover:border-gray-300'
                } bg-gray-900`}
              >
                <div className="w-full h-12 bg-gray-800 rounded-md mb-2"></div>
                <p className="text-sm font-medium text-white">Dark</p>
              </button>
            </div>
            
            <div className="mt-4 p-3 rounded-md bg-blue-50 border border-blue-200">
              <p className="text-xs text-blue-700">
                💡 Your theme preference is saved in the database and will be applied to all pages automatically.
              </p>
            </div>
          </div>

          {/* Logout Section */}
          <div className="mt-8 pt-6 border-t border-gray-200">
            <div className="flex items-center justify-between flex-wrap gap-4">
              <button
                onClick={() => router.push('/dashboard')}
                className="text-green-600 hover:text-green-800 font-medium transition"
              >
                ← Back to Dashboard
              </button>
              
              <button
                onClick={() => setShowLogoutConfirm(true)}
                className="px-6 py-2 text-sm font-medium text-white bg-red-500 rounded-lg hover:bg-red-600 transition flex items-center gap-2"
              >
                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" />
                </svg>
                Logout
              </button>
            </div>
          </div>
        </div>
      </div>

      {/* Logout Confirmation Modal */}
      {showLogoutConfirm && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
          <div className="bg-white rounded-lg shadow-xl max-w-md w-full p-6 mx-4">
            <div className="flex justify-between items-center mb-4">
              <h2 className="text-xl font-bold text-gray-900">Confirm Logout</h2>
              <button
                onClick={() => setShowLogoutConfirm(false)}
                className="text-gray-400 hover:text-gray-600"
              >
                <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>
            
            <div className="mb-6">
              <p className="text-gray-600">
                Are you sure you want to logout? You will be redirected to the login page.
              </p>
            </div>

            <div className="flex justify-end space-x-3">
              <button
                onClick={() => setShowLogoutConfirm(false)}
                className="px-4 py-2 text-sm font-medium text-gray-700 bg-gray-100 rounded-lg hover:bg-gray-200 transition"
              >
                Cancel
              </button>
              <button
                onClick={handleLogout}
                disabled={loggingOut}
                className="px-6 py-2 text-sm font-medium text-white bg-red-500 rounded-lg hover:bg-red-600 transition disabled:opacity-50"
              >
                {loggingOut ? 'Logging out...' : 'Yes, Logout'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}