// app/reports/page.js
'use client';

import Link from 'next/link';

export default function ReportsPage() {
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Reports</h1>
        <p className="text-sm text-gray-500">View system reports and analytics</p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
        <Link href="/reports/sales" className="bg-white rounded-xl shadow-sm p-6 border border-gray-100 hover:shadow-md transition">
          <div className="text-center">
            <div className="text-3xl mb-2">📈</div>
            <h3 className="font-semibold text-gray-900">Sales Report</h3>
            <p className="text-sm text-gray-500">View sales data</p>
          </div>
        </Link>

        <div className="bg-white rounded-xl shadow-sm p-6 border border-gray-100 opacity-50 cursor-not-allowed">
          <div className="text-center">
            <div className="text-3xl mb-2">🚗</div>
            <h3 className="font-semibold text-gray-900">Driver Performance</h3>
            <p className="text-sm text-gray-500">Coming soon</p>
          </div>
        </div>

        <div className="bg-white rounded-xl shadow-sm p-6 border border-gray-100 opacity-50 cursor-not-allowed">
          <div className="text-center">
            <div className="text-3xl mb-2">💰</div>
            <h3 className="font-semibold text-gray-900">Financial Summary</h3>
            <p className="text-sm text-gray-500">Coming soon</p>
          </div>
        </div>

        <div className="bg-white rounded-xl shadow-sm p-6 border border-gray-100 opacity-50 cursor-not-allowed">
          <div className="text-center">
            <div className="text-3xl mb-2">📊</div>
            <h3 className="font-semibold text-gray-900">Daily Report</h3>
            <p className="text-sm text-gray-500">Coming soon</p>
          </div>
        </div>
      </div>
    </div>
  );
}