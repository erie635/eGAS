'use client';

import { useState } from 'react';
import { auth, db } from '../../lib/firebase';
import {
  signInWithEmailAndPassword,
  signOut,
} from 'firebase/auth';
import { doc, getDoc, setDoc } from 'firebase/firestore';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import toast from 'react-hot-toast';

export default function Login() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const router = useRouter();

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();

    if (loading) return;

    setLoading(true);
    setError('');

    const trimmedEmail = email.trim().toLowerCase();
    const trimmedPassword = password.trim();

    // Validate inputs before attempting login
    if (!trimmedEmail || !trimmedPassword) {
      setError('Please enter both email and password.');
      toast.error('Missing credentials');
      setLoading(false);
      return;
    }

    try {
      console.clear();

      console.log('========== LOGIN ==========');
      console.log('Project:', auth.app.options.projectId);
      console.log('Email:', trimmedEmail);
      console.log('Password Length:', trimmedPassword.length);

      // Attempt sign in
      const userCredential = await signInWithEmailAndPassword(
        auth,
        trimmedEmail,
        trimmedPassword
      );

      const user = userCredential.user;

      console.log('Login successful:', user.uid);

      // Get Firestore user document
      const userRef = doc(db, 'users', user.uid);
      let userDoc = await getDoc(userRef);

      // If user document doesn't exist, create one with admin role
      if (!userDoc.exists()) {
        console.log('User document missing. Creating with admin role...');
        
        await setDoc(userRef, {
          name: user.displayName || trimmedEmail.split('@')[0],
          email: trimmedEmail,
          role: 'admin',
          createdAt: new Date().toISOString(),
          updatedAt: new Date().toISOString()
        });
        
        console.log('User document created with admin role');
      } else {
        // If document exists but doesn't have admin role, update it
        const userData = userDoc.data();
        if (userData.role !== 'admin' && userData.role !== 'super_admin') {
          console.log('Updating user role to admin...');
          await setDoc(userRef, {
            ...userData,
            role: 'admin',
            updatedAt: new Date().toISOString()
          }, { merge: true });
          console.log('User role updated to admin');
        }
      }

      // Login successful - redirect to dashboard
      toast.success('Welcome!');
      router.push('/dashboard');
      
    } catch (err: any) {
      // Handle all errors gracefully without console noise
      console.log('================================');
      console.log('Login attempt failed');
      console.log('Code:', err.code);
      console.log('Message:', err.message);
      console.log('================================');

      switch (err.code) {
        case 'auth/invalid-email':
          setError('Invalid email address. Please enter a valid email.');
          toast.error('Invalid email');
          break;

        case 'auth/user-not-found':
          setError('No account found with this email. Please sign up first.');
          toast.error('Account not found');
          break;

        case 'auth/wrong-password':
          setError('Incorrect password. Please try again.');
          toast.error('Wrong password');
          break;

        case 'auth/invalid-credential':
          setError('Incorrect email or password. Please try again.');
          toast.error('Invalid email or password');
          break;

        case 'auth/user-disabled':
          setError('This account has been disabled. Please contact support.');
          toast.error('User disabled');
          break;

        case 'auth/network-request-failed':
          setError('Network error. Please check your internet connection.');
          toast.error('Network error');
          break;

        case 'auth/too-many-requests':
          setError('Too many failed attempts. Please try again later.');
          toast.error('Too many attempts');
          break;

        default:
          setError('Login failed. Please try again.');
          toast.error('Login failed');
      }
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-100">
      <div className="bg-white p-8 rounded-lg shadow-lg w-full max-w-md">
        <div className="text-center mb-8">
          <div className="w-24 h-24 bg-white rounded-full flex items-center justify-center mx-auto mb-4">
            <img src="/images/logo.png" alt="Logo" className="w-25 h-25 object-contain" />
          </div>

          <h1 className="text-2xl font-bold text-gray-800">
            Admin Login
          </h1>

          <p className="text-gray-500 text-sm mt-2">
            Sign in to manage your fuel delivery system
          </p>
        </div>

        {error && (
          <div className="mb-4 p-3 bg-red-50 border border-red-400 text-red-700 rounded-md">
            {error}
          </div>
        )}

        <form onSubmit={handleLogin}>
          <div className="mb-4">
            <label className="block text-sm font-medium text-gray-700 mb-2">
              Email Address
            </label>

            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="admin@efuel.com"
              className="w-full px-4 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-green-500"
              required
            />
          </div>

          <div className="mb-6">
            <label className="block text-sm font-medium text-gray-700 mb-2">
              Password
            </label>

            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="Enter your password"
              className="w-full px-4 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-green-500"
              required
            />
          </div>

          <button
            type="submit"
            disabled={loading}
            className="w-full bg-green-500 hover:bg-green-600 text-white font-semibold py-3 px-4 rounded-md transition disabled:opacity-50"
          >
            {loading ? 'Logging in...' : 'Sign In'}
          </button>
        </form>

        <div className="mt-6 text-center space-y-2">
          <p className="text-sm text-gray-500">
            Don't have an account?{' '}
            <Link
              href="/signup"
              className="text-green-600 hover:text-green-800 font-medium"
            >
              Sign Up
            </Link>
          </p>

          <p className="text-xs text-gray-400">
            Need help? Contact your system administrator
          </p>
        </div>
      </div>
    </div>
  );
}