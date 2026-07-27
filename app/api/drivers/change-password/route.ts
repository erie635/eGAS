import { NextRequest, NextResponse } from 'next/server';
import { getAuth } from 'firebase-admin/auth';
import { initializeApp, getApps, cert } from 'firebase-admin/app';

// Initialize Firebase Admin if not already initialized
if (!getApps().length) {
  initializeApp({
    credential: cert({
      projectId: process.env.FIREBASE_PROJECT_ID,
      clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
      privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
    }),
  });
}

export async function POST(request: NextRequest) {
  try {
    const { email, newPassword } = await request.json();

    if (!email || !newPassword) {
      return NextResponse.json(
        { error: 'Email and new password are required' },
        { status: 400 }
      );
    }

    if (newPassword.length < 6) {
      return NextResponse.json(
        { error: 'Password must be at least 6 characters' },
        { status: 400 }
      );
    }

    const auth = getAuth();

    try {
      // Get user by email
      const userRecord = await auth.getUserByEmail(email);
      
      // Update user's password
      await auth.updateUser(userRecord.uid, {
        password: newPassword,
      });

      return NextResponse.json({
        success: true,
        message: 'Password updated successfully',
        uid: userRecord.uid
      });

    } catch (error: any) {
      // If user not found, create new user
      if (error.code === 'auth/user-not-found') {
        try {
          const newUser = await auth.createUser({
            email: email,
            password: newPassword,
          });

          return NextResponse.json({
            success: true,
            message: 'Driver account created and password set',
            uid: newUser.uid,
            created: true
          });
        } catch (createError: any) {
          return NextResponse.json(
            { error: 'Failed to create driver account: ' + createError.message },
            { status: 500 }
          );
        }
      }

      return NextResponse.json(
        { error: error.message || 'Failed to update password' },
        { status: 500 }
      );
    }

  } catch (error: any) {
    console.error('❌ Error in change-password API:', error);
    return NextResponse.json(
      { error: 'Internal server error: ' + error.message },
      { status: 500 }
    );
  }
}