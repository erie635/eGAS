'use client';

import { useState, useEffect } from 'react';
import { auth, db } from '../../lib/firebase';
import { onAuthStateChanged } from 'firebase/auth';
import { collection, onSnapshot, doc, getDoc } from 'firebase/firestore';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import toast from 'react-hot-toast';

// Mock data – replace with your actual API calls
const branches = [
  { id: 1, name: "Main Branch", studentCount: 45 },
  { id: 2, name: "North Branch", studentCount: 32 },
  { id: 3, name: "South Branch", studentCount: 28 },
  { id: 4, name: "East Branch", studentCount: 19 },
];

// Category configuration with updated terms
const menuCategories = [
  {
    name: "Customer Care",
    items: [
      { name: "Sales Report", href: "/reports/sales" },
    ],
  },
  {
    name: "Director",
    items: [
      { name: "View Tanks", href: "/fuel/tanks" },
      { name: "Comprehensive Report", href: "/dashboard/comprehensive-report" },
    ],
  },
  {
    name: "Drivers Portal",
    items: [
      { name: "View Drivers", href: "/drivers" },
      { name: "Daily Activity", href: "/dashboard/daily-activity" },
    ],
  },
  {
    name: "HR Management",
    items: [
      { name: "Add Driver", href: "/drivers/add" },
    ],
  },
  {
    name: "Fuel Management",
    items: [
      { name: "Company Stock", href: "/fuel/company-stock" },
      { name: "Import Fuel", href: "/fuel/import" },
    ],
  },
];

// Allowed paths that users can access
const ALLOWED_PATHS: string[] = [
  "/dashboard",
  "/reports/sales",
  "/fuel/tanks",
  "/drivers",
  "/drivers/add",
  "/fuel/company-stock",
  "/fuel/import",
  "/dashboard/daily-activity",
  "/dashboard/comprehensive-report",
  "/settings",
];

export default function Dashboard() {
  const router = useRouter();
  const [loading, setLoading] = useState(true);
  const [user, setUser] = useState(null);
  const [totalStock, setTotalStock] = useState({
    Petrol: 0,
    Diesel: 0,
    Kerosene: 0,
    'V-Power': 0
  });
  const [fuelLoading, setFuelLoading] = useState(true);
  const [userBackground, setUserBackground] = useState('white');

  // Menu state
  const [showBranchSelection, setShowBranchSelection] = useState(false);
  const [selectedBranch, setSelectedBranch] = useState<{
    id: number;
    name: string;
    studentCount: number;
  } | null>(null);
  const [studentCount, setStudentCount] = useState<number | null>(null);
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
  const [openCategory, setOpenCategory] = useState<string | null>(null);

  // Track visited pages history
  const [visitedPages, setVisitedPages] = useState<string[]>([]);

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

  // Authentication check
  useEffect(() => {
    const unsubscribe = onAuthStateChanged(auth, (currentUser) => {
      if (!currentUser) {
        router.push('/login');
      } else {
        setUser(currentUser);
        setLoading(false);
      }
    });

    return () => unsubscribe();
  }, [router]);

  // Real-time fuel tank updates from drivers
  useEffect(() => {
    const unsubscribe = onSnapshot(collection(db, 'drivers'), (snapshot) => {
      const drivers = snapshot.docs.map(doc => doc.data());
      const stock = { Petrol: 0, Diesel: 0, Kerosene: 0, 'V-Power': 0 };

      drivers.forEach(driver => {
        if (driver.remainingFuel) {
          Object.keys(stock).forEach(key => {
            stock[key] += driver.remainingFuel[key] || 0;
          });
        }
      });

      setTotalStock(stock);
      setFuelLoading(false);
    });

    return () => unsubscribe();
  }, []);

  // Initialize visited pages
  useEffect(() => {
    if (!user) return;

    const storedVisited = sessionStorage.getItem("visitedPages");
    if (storedVisited) {
      const parsed = JSON.parse(storedVisited);
      setVisitedPages(parsed);
    } else if (typeof window !== 'undefined') {
      const initialVisited = [window.location.pathname];
      setVisitedPages(initialVisited);
      sessionStorage.setItem("visitedPages", JSON.stringify(initialVisited));
    }
  }, [user]);

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
        return 'bg-gray-800/95 border-gray-700';
      case 'skyblue':
        return 'bg-white/90 backdrop-blur-sm shadow-lg';
      case 'gray':
        return 'bg-white shadow-lg';
      default:
        return 'bg-white shadow-lg';
    }
  };

  // Function to reset everything to fresh state
  const resetAllState = () => {
    setShowBranchSelection(false);
    setSelectedBranch(null);
    setStudentCount(null);
    setMobileMenuOpen(false);
    setOpenCategory(null);
  };

  const resetBranchSelection = () => {
    setShowBranchSelection(false);
    setSelectedBranch(null);
    setStudentCount(null);
  };

  const handleStudentClick = () => {
    resetBranchSelection();
    setShowBranchSelection(true);
    setOpenCategory(null);
    setMobileMenuOpen(false);
  };

  const handleBranchSelect = (branch: (typeof branches)[0]) => {
    setSelectedBranch(branch);
    setStudentCount(branch.studentCount);
  };

  const scrollToTop = () => {
    window.scrollTo({ top: 0, behavior: "smooth" });
  };

  const toggleCategory = (categoryName: string) => {
    setOpenCategory(openCategory === categoryName ? null : categoryName);
    setShowBranchSelection(false);
  };

  const handleLinkClick = (href: string) => {
    setOpenCategory(null);
    setShowBranchSelection(false);
    setMobileMenuOpen(false);
    resetBranchSelection();

    if (ALLOWED_PATHS.includes(href)) {
      router.push(href);
    } else {
      console.warn(`Access denied to: ${href}`);
      router.push("/dashboard");
    }
  };

  // Show loading while checking authentication
  if (loading || fuelLoading) {
    return (
      <div className={`flex items-center justify-center min-h-[60vh] ${getBackgroundClass()}`}>
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-green-500"></div>
      </div>
    );
  }

  return (
    <>
      <style>{`
        body, .dashboard-container, .dashboard-main-inner, button, a, p, h1, h2, h3, h4, span, li {
          font-size: 14px;
        }
        @media (max-width: 768px) {
          body, .dashboard-container, .dashboard-main-inner, button, a, p, h1, h2, h3, h4, span, li {
            font-size: 12px;
          }
        }

        .dashboard-container {
          flex-direction: column !important;
        }
        
        .dashboard-main {
          padding: 0.5rem !important;
        }
        
        .dashboard-main-inner {
          padding: 0.75rem !important;
        }
        
        .grid.grid-cols-1.md\\:grid-cols-2.gap-5 {
          gap: 0.75rem !important;
        }
        
        .bg-gray-50.hover\\:bg-indigo-50.transition-all.p-5.rounded-xl {
          padding: 0.75rem !important;
        }
        
        .text-gray-800.font-semibold.text-lg {
          font-size: 0.9rem !important;
        }
        
        .text-gray-500.text-sm.mt-1 {
          font-size: 0.7rem !important;
        }
        
        .mt-6.p-5.bg-indigo-50.rounded-xl {
          padding: 0.75rem !important;
        }
        
        .text-gray-800.text-base {
          font-size: 0.85rem !important;
        }
        
        button.px-4.py-2 {
          padding: 0.3rem 0.75rem !important;
          font-size: 0.75rem !important;
        }

        @media (min-width: 769px) {
          .dashboard-main {
            padding: 1rem !important;
          }
          .dashboard-main-inner {
            padding: 1.5rem !important;
          }
          body, .dashboard-container, .dashboard-main-inner, button, a, p, span, li {
            font-size: 15px;
          }
        }

        /* Desktop Top Menu Bar */
        .top-menu-bar {
          position: sticky;
          top: 0;
          left: 0;
          right: 0;
          background: #1a1a2e;
          border-bottom: 1px solid #e5e7eb;
          box-shadow: 0 1px 3px rgba(0,0,0,0.5);
          z-index: 9998;
          padding: 0.75rem 1rem;
          display: flex;
          gap: 0.5rem;
          overflow-x: auto;
          overflow-y: hidden;
          white-space: nowrap;
          align-items: center;
          scrollbar-width: thin;
          -webkit-overflow-scrolling: touch;
        }
        
        @media (min-width: 769px) {
          .top-menu-bar::-webkit-scrollbar {
            height: 4px;
          }
          .top-menu-bar::-webkit-scrollbar-track {
            background: transparent;
          }
          .top-menu-bar::-webkit-scrollbar-thumb {
            background: transparent;
            border-radius: 10px;
          }
          .top-menu-bar:hover::-webkit-scrollbar-thumb {
            background: #c1c1c1;
          }
          .top-menu-bar:hover::-webkit-scrollbar-thumb:hover {
            background: #a8a8a8;
          }
        }
        
        /* Hide desktop menu on mobile */
        @media (max-width: 768px) {
          .top-menu-bar, .dropdown-panel { 
            display: none !important; 
          }
        }
        
        /* ========== MOBILE MENU - FIXED TO VIEWPORT ========== */
        .mobile-menu-btn {
          position: fixed !important;
          top: 8px !important;
          left: 8px !important;
          z-index: 99999 !important;
          background: #1877F2;
          border: none;
          border-radius: 30px;
          padding: 6px 14px;
          cursor: pointer;
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 6px;
          box-shadow: 0 2px 10px rgba(0,0,0,0.25);
          transition: all 0.2s ease;
          color: white;
          font-weight: 600;
          font-family: system-ui, -apple-system, 'Segoe UI', Roboto;
          font-size: 13px;
        }
        
        .mobile-menu-btn svg {
          width: 16px;
          height: 16px;
          stroke: white;
        }
        
        .mobile-menu-btn span {
          font-size: 13px;
          letter-spacing: 0.3px;
        }
        
        .mobile-menu-btn:active {
          transform: scale(0.96);
          background: #0e5ec7;
        }
        
        /* Mobile horizontal sliding menu */
        .mobile-horizontal-menu {
          position: fixed !important;
          top: 48px !important;
          left: 0 !important;
          right: 0 !important;
          background: #ffffff;
          border-bottom: 1px solid #e9ecef;
          box-shadow: 0 8px 25px rgba(0,0,0,0.15);
          z-index: 99998 !important;
          transform: translateY(-200%);
          transition: transform 0.28s cubic-bezier(0.2, 0.9, 0.4, 1.1);
          overflow-x: auto;
          overflow-y: hidden;
          -webkit-overflow-scrolling: touch;
          scrollbar-width: thin;
        }
        
        /* Scrollable content wrapper */
        .mobile-menu-scroll-wrapper {
          display: flex;
          gap: 8px;
          align-items: center;
          white-space: nowrap;
          padding: 8px 12px;
          min-width: max-content;
        }
        
        .mobile-horizontal-menu::-webkit-scrollbar {
          height: 3px;
        }
        
        .mobile-horizontal-menu::-webkit-scrollbar-track {
          background: #f1f1f1;
        }
        
        .mobile-horizontal-menu::-webkit-scrollbar-thumb {
          background: #c1c1c1;
          border-radius: 10px;
        }
        
        .mobile-horizontal-menu.open {
          transform: translateY(0);
        }
        
        /* STICKY LOGO */
        .mobile-menu-logo {
          position: sticky !important;
          left: 0 !important;
          background: white !important;
          z-index: 10 !important;
          font-weight: 700;
          font-size: 13px;
          color: #1877F2;
          padding-right: 10px;
          margin-right: 6px;
          border-right: 1.5px solid #e2e8f0;
          flex-shrink: 0;
          display: flex;
          align-items: center;
          gap: 5px;
        }
        
        .mobile-menu-item {
          padding: 5px 14px;
          cursor: pointer;
          font-weight: 500;
          color: #1f2937;
          background: #f3f4f6;
          border-radius: 30px;
          transition: all 0.2s ease;
          font-size: 12px;
          flex-shrink: 0;
          white-space: nowrap;
        }
        
        .mobile-menu-item:hover {
          background: #e0e7ff;
          color: #1877F2;
        }
        
        .mobile-menu-item.active {
          background: #1877F2 !important;
          color: white !important;
        }
        
        /* Mobile Dropdown Panel */
        .mobile-dropdown-panel {
          position: fixed !important;
          top: 92px !important;
          left: 0 !important;
          right: 0 !important;
          background: #f8fafc;
          border-bottom: 2px solid #1877F2;
          box-shadow: 0 8px 20px rgba(0,0,0,0.15);
          z-index: 99997 !important;
          padding: 8px 12px;
          display: flex;
          gap: 8px;
          overflow-x: auto;
          overflow-y: hidden;
          white-space: nowrap;
          flex-direction: row;
          flex-wrap: nowrap;
          -webkit-overflow-scrolling: touch;
          transform: translateY(-100%);
          transition: transform 0.28s cubic-bezier(0.2, 0.9, 0.4, 1.1);
        }
        
        .mobile-dropdown-panel.open {
          transform: translateY(0);
        }
        
        .mobile-dropdown-panel::-webkit-scrollbar {
          height: 3px;
        }
        
        .mobile-dropdown-panel::-webkit-scrollbar-track {
          background: #e2e8f0;
          border-radius: 10px;
        }
        
        .mobile-dropdown-panel::-webkit-scrollbar-thumb {
          background: #1877F2;
          border-radius: 10px;
        }
        
        .mobile-dropdown-item {
          padding: 5px 14px;
          color: #1e293b;
          text-decoration: none;
          border-radius: 30px;
          transition: all 0.2s ease;
          font-size: 12px;
          background: white;
          flex-shrink: 0;
          white-space: nowrap;
          font-weight: 600;
          cursor: pointer;
          border: 1px solid #e2e8f0;
          box-shadow: 0 1px 2px rgba(0,0,0,0.05);
        }
        
        .mobile-dropdown-item:hover {
          background: #1877F2;
          color: white;
          border-color: #1877F2;
          transform: scale(1.02);
        }
        
        @keyframes slideDown {
          from { opacity: 0; transform: translateY(-10px); }
          to { opacity: 1; transform: translateY(0); }
        }
        
        /* Desktop original styles */
        .menu-logo {
          font-weight: bold;
          font-size: 1.1rem;
          color: #FFD700;
          padding-right: 1rem;
          border-right: 1px solid #e5e7eb;
          margin-right: 0.5rem;
          flex-shrink: 0;
        }
        
        .top-menu-item {
          padding: 0.5rem 1rem;
          cursor: pointer;
          font-weight: 500;
          color: #ffffff;
          border-radius: 0.5rem;
          transition: all 0.2s ease;
          flex-shrink: 0;
          white-space: nowrap;
        }
        
        .top-menu-item:hover {
          background: #4a4a6a;
          color: #fff;
        }
        
        .top-menu-item.active {
          background: #22c55e !important;
          color: white !important;
        }
        
        .dropdown-panel {
          position: sticky;
          top: 52px;
          left: 0;
          right: 0;
          background: white;
          border-bottom: 1px solid #808080;
          box-shadow: 0 4px 6px -1px rgba(0,0,0,0.1);
          z-index: 9996;
          padding: 0.75rem 1rem;
          display: flex;
          gap: 0.5rem;
          overflow-x: auto;
          overflow-y: hidden;
          white-space: nowrap;
          animation: slideDown 0.2s ease;
          scrollbar-width: thin;
          -webkit-overflow-scrolling: touch;
        }
        
        @media (min-width: 769px) {
          .dropdown-panel::-webkit-scrollbar {
            height: 4px;
          }
          .dropdown-panel::-webkit-scrollbar-track {
            background: transparent;
          }
          .dropdown-panel::-webkit-scrollbar-thumb {
            background: transparent;
            border-radius: 10px;
          }
          .dropdown-panel:hover::-webkit-scrollbar-thumb {
            background: #c1c1c1;
          }
          .dropdown-panel:hover::-webkit-scrollbar-thumb:hover {
            background: #a8a8a8;
          }
        }
        
        .dropdown-item {
          padding: 0.5rem 1rem;
          color: #4b5563;
          text-decoration: none;
          border-radius: 0.5rem;
          transition: all 0.2s ease;
          font-size: 0.875rem;
          flex-shrink: 0;
          white-space: nowrap;
          cursor: pointer;
        }
        
        .dropdown-item:hover {
          background: #e0e7ff;
          color: #4f46e5;
        }
        
        .user-profile {
          margin-left: auto;
          display: flex;
          align-items: center;
          gap: 0.75rem;
          flex-shrink: 0;
        }
        
        /* Hide mobile elements on desktop */
        @media (min-width: 769px) {
          .mobile-menu-btn, .mobile-horizontal-menu, .mobile-dropdown-panel { display: none !important; }
        }
        
        .dashboard-main { transition: margin-top 0.3s ease; }
        
        .top-menu-bar, .dropdown-panel, .mobile-horizontal-menu, .mobile-dropdown-panel {
          scroll-behavior: smooth;
        }
        
        /* Ensure content has proper spacing */
        @media (max-width: 768px) {
          .dashboard-container {
            padding-top: 55px !important;
          }
        }
      `}</style>

      {/* Desktop Top Menu Bar */}
      <div className="top-menu-bar">
        <div className="menu-logo">⚡ FuelTrack</div>
        {menuCategories.map((category) => (
          <div
            key={category.name}
            className={`top-menu-item ${openCategory === category.name ? "active" : ""}`}
            onClick={() => toggleCategory(category.name)}
          >
            {category.name}
          </div>
        ))}
        <div
          className={`top-menu-item ${showBranchSelection ? "active" : ""}`}
          onClick={handleStudentClick}
        >
          Branch Label
        </div>
        <div className="user-profile">
          <Link href="/settings" className="text-gray-400 hover:text-white transition p-1">
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
            </svg>
          </Link>
          <div className="w-8 h-8 rounded-full bg-gradient-to-r from-green-500 to-teal-500 flex items-center justify-center text-white font-bold shadow-sm text-sm">
            {user?.displayName?.charAt(0) || user?.email?.charAt(0) || 'U'}
          </div>
          <button onClick={scrollToTop} className="text-gray-400 hover:text-gray-600 transition">
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 15l7-7 7 7" />
            </svg>
          </button>
        </div>
      </div>

      {/* Desktop Dropdown Panels */}
      {openCategory && (
        <div className="dropdown-panel">
          {menuCategories.find(c => c.name === openCategory)?.items.map((item) => (
            <div
              key={item.name}
              className="dropdown-item"
              onClick={() => handleLinkClick(item.href)}
              style={{ cursor: "pointer" }}
            >
              {item.name}
            </div>
          ))}
        </div>
      )}

      {showBranchSelection && !openCategory && (
        <div className="dropdown-panel">
          <div className="flex gap-3 flex-nowrap overflow-x-auto w-full">
            {branches.map((branch) => (
              <button key={branch.id} onClick={() => handleBranchSelect(branch)} className="px-4 py-2 bg-gray-50 hover:bg-indigo-50 rounded-lg text-sm transition border border-gray-200 flex-shrink-0 whitespace-nowrap">
                {branch.name}
              </button>
            ))}
          </div>
          {selectedBranch && studentCount !== null && (
            <div className="mt-3 w-full p-3 bg-indigo-50 rounded-lg flex items-center justify-between">
              <span className="text-sm"><span className="font-semibold">{selectedBranch.name}</span> has <span className="font-bold text-indigo-600">{studentCount}</span> students</span>
              <button onClick={() => { setSelectedBranch(null); setStudentCount(null); }} className="px-3 py-1 bg-white hover:bg-gray-100 rounded-lg text-sm transition border border-gray-200">
                Clear
              </button>
            </div>
          )}
        </div>
      )}

      {/* ========== MOBILE MENU BUTTON ========== */}
      <button onClick={() => setMobileMenuOpen(!mobileMenuOpen)} className="mobile-menu-btn" aria-label="Toggle menu">
        <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          {mobileMenuOpen ? (
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
          ) : (
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6h16M4 12h16M4 18h16" />
          )}
        </svg>
        <span>Menu</span>
      </button>

      {/* Mobile Horizontal Menu */}
      <div className={`mobile-horizontal-menu ${mobileMenuOpen ? "open" : ""}`}>
        <div className="mobile-menu-scroll-wrapper">
          <div className="mobile-menu-logo">
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 10V3L4 14h7v7l9-11h-7z" />
            </svg>
            FuelTrack
          </div>
          {menuCategories.map((category) => (
            <div
              key={category.name}
              className={`mobile-menu-item ${openCategory === category.name ? "active" : ""}`}
              onClick={() => {
                toggleCategory(category.name);
                setMobileMenuOpen(true);
              }}
            >
              {category.name}
            </div>
          ))}
          <div
            className={`mobile-menu-item ${showBranchSelection ? "active" : ""}`}
            onClick={() => {
              handleStudentClick();
              setMobileMenuOpen(true);
            }}
          >
            Branch Label
          </div>
          <Link
            href="/settings"
            className="mobile-menu-item"
            onClick={() => setMobileMenuOpen(false)}
          >
            ⚙️ Settings
          </Link>
        </div>
      </div>

      {/* Mobile Dropdown Panels */}
      {openCategory && (
        <div className={`mobile-dropdown-panel ${openCategory ? "open" : ""}`}>
          {menuCategories.find(c => c.name === openCategory)?.items.map((item) => (
            <div
              key={item.name}
              className="mobile-dropdown-item"
              onClick={() => {
                handleLinkClick(item.href);
                setMobileMenuOpen(false);
                setOpenCategory(null);
              }}
              style={{ cursor: "pointer" }}
            >
              {item.name}
            </div>
          ))}
        </div>
      )}

      {showBranchSelection && !openCategory && (
        <div className={`mobile-dropdown-panel ${showBranchSelection ? "open" : ""}`}>
          <div className="flex gap-2 flex-nowrap overflow-x-auto w-full">
            {branches.map((branch) => (
              <button
                key={branch.id}
                onClick={() => {
                  handleBranchSelect(branch);
                  setShowBranchSelection(false);
                }}
                className="px-3 py-1.5 bg-gray-50 hover:bg-indigo-50 rounded-lg text-xs transition border border-gray-200 flex-shrink-0 whitespace-nowrap"
              >
                {branch.name}
              </button>
            ))}
          </div>
          {selectedBranch && studentCount !== null && (
            <div className="mt-2 w-full p-2 bg-indigo-50 rounded-lg flex items-center justify-between">
              <span className="text-xs"><span className="font-semibold">{selectedBranch.name}</span> has <span className="font-bold text-indigo-600">{studentCount}</span> students</span>
              <button onClick={() => { setSelectedBranch(null); setStudentCount(null); }} className="px-2 py-1 bg-white hover:bg-gray-100 rounded-lg text-xs transition border border-gray-200">
                Clear
              </button>
            </div>
          )}
        </div>
      )}

      {/* Main content with transparent background */}
      <div className={`relative min-h-screen ${getBackgroundClass()} dashboard-container`} style={{ paddingTop: '55px' }}>
        <main className="flex-1 p-2 overflow-auto dashboard-main">
          <div className={`rounded-2xl shadow-sm border p-6 dashboard-main-inner ${getCardClass()}`}>
            {showBranchSelection ? (
              <div className="space-y-6">
                <h2 className={`text-2xl font-bold ${userBackground === 'dark' ? 'text-white' : 'text-gray-800'}`}>Select a Branch</h2>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-5">
                  {branches.map((branch) => (
                    <button key={branch.id} onClick={() => handleBranchSelect(branch)} className={`${userBackground === 'dark' ? 'bg-gray-700 hover:bg-gray-600 text-white' : 'bg-gray-50 hover:bg-indigo-50 text-gray-800'} transition-all p-5 rounded-xl text-left border ${userBackground === 'dark' ? 'border-gray-600 hover:border-gray-500' : 'border-gray-200 hover:border-indigo-200'} shadow-sm hover:shadow`}>
                      <div className={`font-semibold text-lg ${userBackground === 'dark' ? 'text-white' : 'text-gray-800'}`}>{branch.name}</div>
                      <div className={`text-sm mt-1 ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>Click to view student count</div>
                    </button>
                  ))}
                </div>
                {selectedBranch && studentCount !== null && (
                  <div className={`mt-6 p-5 rounded-xl border ${userBackground === 'dark' ? 'bg-blue-900/30 border-blue-700 text-blue-200' : 'bg-indigo-50 border-indigo-100'}`}>
                    <p className={`text-base ${userBackground === 'dark' ? 'text-blue-200' : 'text-gray-800'}`}><span className="font-semibold">{selectedBranch.name}</span> has <span className="font-bold text-indigo-600">{studentCount}</span> students.</p>
                    <button onClick={() => { setSelectedBranch(null); setStudentCount(null); }} className={`mt-3 px-4 py-2 rounded-lg text-sm transition border ${userBackground === 'dark' ? 'bg-gray-700 hover:bg-gray-600 text-white border-gray-600' : 'bg-white hover:bg-gray-100 text-gray-700 border-gray-200'}`}>
                      Clear selection
                    </button>
                  </div>
                )}
                <button onClick={() => setShowBranchSelection(false)} className={`mt-4 px-5 py-2 rounded-lg text-sm transition font-medium ${userBackground === 'dark' ? 'bg-gray-700 hover:bg-gray-600 text-white' : 'bg-gray-100 hover:bg-gray-200 text-gray-700'}`}>
                  ← Back to dashboard
                </button>
              </div>
            ) : (
              <div className="space-y-6 pb-20">
                {/* Header */}
                <div>
                  <h1 className={`text-2xl font-bold ${userBackground === 'dark' ? 'text-white' : 'text-gray-900'}`}>Dashboard</h1>
                  <p className={`text-sm ${userBackground === 'dark' ? 'text-gray-400' : 'text-gray-500'}`}>Welcome, {user?.displayName || user?.email || 'User'}!</p>
                </div>

                {/* Stats Grid */}
                <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
                  <div className="rounded-xl shadow-sm p-6 border bg-green-400 border-green-300">
                    <div className="flex items-center justify-between">
                      <div>
                        <p className="text-sm font-medium text-gray-800">Total Drivers</p>
                        <p className="text-2xl font-bold mt-1 text-gray-900">0</p>
                      </div>
                      <div className="w-12 h-12 rounded-full bg-green-200 flex items-center justify-center">
                        <svg className="w-6 h-6 text-green-700" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z" />
                        </svg>
                      </div>
                    </div>
                  </div>

                  <div className="rounded-xl shadow-sm p-6 border bg-blue-400 border-blue-300">
                    <div className="flex items-center justify-between">
                      <div>
                        <p className="text-sm font-medium text-gray-800">Total Orders</p>
                        <p className="text-2xl font-bold mt-1 text-gray-900">0</p>
                      </div>
                      <div className="w-12 h-12 rounded-full bg-blue-200 flex items-center justify-center">
                        <svg className="w-6 h-6 text-blue-700" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M16 11V7a4 4 0 00-8 0v4M5 9h14l1 12H4L5 9z" />
                        </svg>
                      </div>
                    </div>
                  </div>

                  <div className="rounded-xl shadow-sm p-6 border bg-yellow-400 border-yellow-300">
                    <div className="flex items-center justify-between">
                      <div>
                        <p className="text-sm font-medium text-gray-800">Total Revenue</p>
                        <p className="text-2xl font-bold mt-1 text-gray-900">KES 0</p>
                      </div>
                      <div className="w-12 h-12 rounded-full bg-yellow-200 flex items-center justify-center">
                        <svg className="w-6 h-6 text-yellow-700" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M17 9V7a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2m2 4h10a2 2 0 002-2v-6a2 2 0 00-2-2H9a2 2 0 00-2 2v6a2 2 0 002 2zm7-5a2 2 0 11-4 0 2 2 0 014 0z" />
                        </svg>
                      </div>
                    </div>
                  </div>

                  <div className="rounded-xl shadow-sm p-6 border bg-red-400 border-red-300">
                    <div className="flex items-center justify-between">
                      <div>
                        <p className="text-sm font-medium text-gray-800">Fuel Sold</p>
                        <p className="text-2xl font-bold mt-1 text-gray-900">0L</p>
                      </div>
                      <div className="w-12 h-12 rounded-full bg-red-200 flex items-center justify-center">
                        <svg className="w-6 h-6 text-red-700" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
                        </svg>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            )}
          </div>
        </main>
      </div>
    </>
  );
}