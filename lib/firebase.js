import { initializeApp, getApps } from 'firebase/app';
import { getFirestore } from 'firebase/firestore';
import { getAuth } from 'firebase/auth';
import { getStorage } from 'firebase/storage';

const firebaseConfig = {
  apiKey: "AIzaSyAKn5X9NZ_4f1x2_cdHUQIt31MKlI3VAvQ",
  authDomain: "efilling-d1456.firebaseapp.com",
  projectId: "efilling-d1456",
  storageBucket: "efilling-d1456.firebasestorage.app",
  messagingSenderId: "352404895374",
  appId: "1:352404895374:web:73d77a3a1ecdef3528fbdf",
  measurementId: "G-VF3VBKG5LX"
};

const app = !getApps().length ? initializeApp(firebaseConfig) : getApps()[0];

export const db = getFirestore(app);
export const auth = getAuth(app);
export const storage = getStorage(app);