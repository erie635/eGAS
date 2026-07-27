'use client';

import { useState, useEffect } from 'react';
import { auth, db } from '../../lib/firebase';
import { createUserWithEmailAndPassword, updateProfile, fetchSignInMethodsForEmail } from 'firebase/auth';
import { doc, setDoc } from 'firebase/firestore';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import toast from 'react-hot-toast';

interface FormData {
  name: string;
  email: string;
  password: string;
  confirmPassword: string;
}

export default function Signup() {
  const [formData, setFormData] = useState<FormData>({
    name: '',
    email: '',
    password: '',
    confirmPassword: ''
  });
  const [loading, setLoading] = useState<boolean>(false);
  const [error, setError] = useState<string>('');
  const [success, setSuccess] = useState<boolean>(false);
  const [emailWarning, setEmailWarning] = useState<string>('');
  const [isEmailValidating, setIsEmailValidating] = useState<boolean>(false);
  const router = useRouter();

  // Debounced email validation on email input change
  useEffect(() => {
    if (!formData.email) {
      setEmailWarning('');
      return;
    }

    setIsEmailValidating(true);

    const timer = setTimeout(async () => {
      try {
        const methods = await fetchSignInMethodsForEmail(auth, formData.email.trim());
        if (methods.length > 0) {
          setEmailWarning('This email is already registered. Please use a different one.');
        } else {
          setEmailWarning('');
        }
      } catch (error) {
        // Optionally handle error, clear warning to not block user unnecessarily
        setEmailWarning('');
      } finally {
        setIsEmailValidating(false);
      }
    }, 700); // 700ms debounce for better UX

    return () => clearTimeout(timer);
  }, [formData.email]);

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const { name, value } = e.target;
    setFormData(prev => ({
      ...prev,
      [name]: value
    }));

    setError('');
  };

  const handleSignup = async (e: React.FormEvent) => {
    e.preventDefault();

    setError('');

    if (!formData.name) {
      setError('Please enter your full name');
      return;
    }

    if (formData.password !== formData.confirmPassword) {
      setError('Passwords do not match');
      return;
    }

    if (formData.password.length < 6) {
      setError('Password must be at least 6 characters');
      return;
    }

    if (emailWarning) {
      setError(emailWarning);
      return;
    }

    setLoading(true);

    try {
      // Optional: Re-check email one last time before signup to reduce race condition errors
      const methods = await fetchSignInMethodsForEmail(auth, formData.email.trim());
      if (methods.length > 0) {
        setError('This email is already registered. Please login instead.');
        toast.error('Email already in use');
        setLoading(false);
        return;
      }

      const userCredential = await createUserWithEmailAndPassword(
        auth,
        formData.email.trim(),
        formData.password
      );

      const user = userCredential.user;

      await updateProfile(user, {
        displayName: formData.name.trim()
      });

      await setDoc(doc(db, 'users', user.uid), {
        name: formData.name.trim(),
        email: formData.email.trim(),
        role: 'user',
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString()
      });

      setSuccess(true);
      toast.success('Account created successfully!');

      setTimeout(() => {
        router.push('/login');
      }, 2000);

    } catch (error: any) {
      // Handle signup errors, including race condition cases
      switch (error.code) {
        case 'auth/email-already-in-use':
          setError('This email is already registered. Please login instead.');
          toast.error('Email already in use');
          break;
        case 'auth/invalid-email':
          setError('Invalid email address. Please enter a valid email.');
          toast.error('Invalid email');
          break;
        case 'auth/weak-password':
          setError('Password is too weak. Please use at least 6 characters.');
          toast.error('Password too weak');
          break;
        case 'auth/network-request-failed':
          setError('Network error. Please check your internet connection.');
          toast.error('Network error');
          break;
        default:
          setError('Failed to create account: ' + error.message);
          toast.error('Signup failed');
      }
    } finally {
      setLoading(false);
    }
  };

  if (success) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-100 py-12 px-4">
        <div className="bg-white p-8 rounded-lg shadow-lg w-full max-w-md text-center">
          <div className="w-28 h-28 bg-white rounded-full flex items-center justify-center mx-auto mb-6">
            <img src="/images/logo.png" alt="Logo" className="w-20 h-20 object-contain" />
          </div>
          <h2 className="text-2xl font-bold text-gray-800 mb-2">✅ Account Created!</h2>
          <p className="text-gray-600 mb-4">Your account has been created successfully.</p>
          <div className="bg-gray-50 p-4 rounded-lg mb-6 text-left">
            <p className="text-sm"><strong>Name:</strong> {formData.name}</p>
            <p className="text-sm"><strong>Email:</strong> {formData.email}</p>
          </div>
          <p className="text-sm text-gray-500">Redirecting to login page...</p>
          <div className="mt-4 w-full bg-gray-200 rounded-full h-2">
            <div className="bg-green-500 h-2 rounded-full animate-pulse" style={{ width: '100%' }}></div>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-100 py-12 px-4">
      <div className="bg-white p-8 rounded-lg shadow-lg w-full max-w-md">
        <div className="text-center mb-8">
          <div className="w-24 h-24 bg-white rounded-full flex items-center justify-center mx-auto mb-4">
            <img src="/images/logo.png" alt="Logo" className="w-25 h-25 object-contain" />
          </div>
          <h1 className="text-2xl font-bold text-gray-800">Create Account</h1>
          <p className="text-gray-500 text-sm mt-2">Create your account to get started</p>
        </div>

        {error && (
          <div className="mb-4 p-3 bg-red-50 border border-red-400 text-red-700 rounded-md text-sm">
            <strong>Error:</strong> {error}
          </div>
        )}

        <form onSubmit={handleSignup}>
          <div className="mb-4">
            <label className="block text-sm font-medium text-gray-700 mb-2">Full Name *</label>
            <input
              type="text"
              name="name"
              value={formData.name}
              onChange={handleChange}
              placeholder="Enter your full name"
              className="w-full px-4 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-green-500"
              required
            />
          </div>
          <div className="mb-4">
            <label className="block text-sm font-medium text-gray-700 mb-2">Email Address *</label>
            <input
              type="email"
              name="email"
              value={formData.email}
              onChange={handleChange}
              placeholder="you@example.com"
              className={`w-full px-4 py-2 border rounded-md focus:outline-none focus:ring-2 ${
                emailWarning ? 'border-red-500 focus:ring-red-500' : 'border-gray-300 focus:ring-green-500'
              }`}
              required
            />
            {emailWarning && (
              <p className="text-xs text-red-600 mt-1">
                {emailWarning}
              </p>
            )}
          </div>
          <div className="mb-4">
            <label className="block text-sm font-medium text-gray-700 mb-2">Password *</label>
            <input
              type="password"
              name="password"
              value={formData.password}
              onChange={handleChange}
              placeholder="Minimum 6 characters"
              className="w-full px-4 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-green-500"
              required
              minLength={6}
            />
            <p className="text-xs text-gray-400 mt-1">Password must be at least 6 characters</p>
          </div>
          <div className="mb-6">
            <label className="block text-sm font-medium text-gray-700 mb-2">Confirm Password *</label>
            <input
              type="password"
              name="confirmPassword"
              value={formData.confirmPassword}
              onChange={handleChange}
              placeholder="Confirm your password"
              className="w-full px-4 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-green-500"
              required
            />
          </div>

          <button
            type="submit"
            disabled={loading || !!emailWarning || isEmailValidating}
            className="w-full bg-green-500 hover:bg-green-600 text-white font-semibold py-3 px-4 rounded-md transition disabled:opacity-50"
          >
            {loading ? 'Creating Account...' : 'Create Account'}
          </button>
        </form>

        <div className="mt-6 text-center">
          <p className="text-sm text-gray-500">
            Already have an account?{' '}
            <Link href="/login" className="text-green-600 hover:text-green-800 font-medium">
              Login here
            </Link>
          </p>
        </div>
      </div>
    </div>
  );
}