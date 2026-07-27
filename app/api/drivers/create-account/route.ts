import { NextRequest, NextResponse } from 'next/server';
import { getAuth } from 'firebase-admin/auth';
import { initializeApp, getApps, cert } from 'firebase-admin/app';

// Initialize Firebase Admin with your exact credentials
function initFirebaseAdmin() {
  try {
    // Check if already initialized
    if (getApps().length > 0) {
      console.log('✅ DB Admin already initialized');
      return;
    }

    console.log('🔄 Initializing DB Admin...');
    
    // Get credentials from environment variables
    const projectId = process.env.FIREBASE_PROJECT_ID;
    const clientEmail = process.env.FIREBASE_CLIENT_EMAIL;
    const privateKey = process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n');

    console.log('📋 Project ID:', projectId);
    console.log('📋 Client Email:', clientEmail);
    console.log('📋 Private Key exists:', !!privateKey);
    console.log('📋 Private Key length:', privateKey?.length || 0);

    // Validate credentials
    if (!projectId || !clientEmail || !privateKey) {
      console.error('❌ Missing DB Admin credentials');
      throw new Error('DB Admin credentials not found');
    }

    // Initialize DB Admin
    initializeApp({
      credential: cert({
        projectId: projectId,
        clientEmail: clientEmail,
        privateKey: privateKey,
      }),
    });

    console.log('✅ DB Admin initialized successfully');
  } catch (error) {
    console.error('❌ Failed to initialize DB Admin:', error);
    throw error;
  }
}

// Initialize on module load
try {
  initFirebaseAdmin();
} catch (error) {
  console.error('❌ DB Admin initialization failed:', error);
}

export async function POST(request: NextRequest) {
  console.log('📥 API: Create/Update Driver Account');
  
  try {
    // Parse request body
    const body = await request.json();
    const { email, password, driverId, name, phone, vehicleType, numberPlate } = body;

    console.log('📧 Email:', email);
    console.log('🔑 Driver ID:', driverId);
    console.log('👤 Name:', name);

    // Validate required fields
    if (!email || !password) {
      return NextResponse.json(
        { error: 'Email and password are required' },
        { status: 400 }
      );
    }

    if (password.length < 6) {
      return NextResponse.json(
        { error: 'Password must be at least 6 characters' },
        { status: 400 }
      );
    }

    // Get DB Auth instance
    const auth = getAuth();
    let uid: string;
    let created = false;

    try {
      // Try to get existing user by email
      console.log('🔍 Checking if user exists:', email);
      const userRecord = await auth.getUserByEmail(email);
      uid = userRecord.uid;
      console.log('✅ User exists with UID:', uid);
      
      // Update password
      console.log('🔄 Updating password for user:', uid);
      await auth.updateUser(uid, {
        password: password,
        displayName: name || undefined,
      });
      console.log('✅ Password updated successfully');

    } catch (error: any) {
      // User not found - create new
      if (error.code === 'auth/user-not-found') {
        console.log('🆕 Creating new user:', email);
        const newUser = await auth.createUser({
          email: email,
          password: password,
          displayName: name || undefined,
        });
        uid = newUser.uid;
        created = true;
        console.log('✅ New user created with UID:', uid);
      } else {
        console.error('❌ DB Auth error:', error);
        throw error;
      }
    }

    // Return success response
    return NextResponse.json({
      success: true,
      message: created ? 'Driver account created successfully' : 'Password updated successfully',
      uid: uid,
      created: created,
      email: email
    });

  } catch (error: any) {
    console.error('❌ API Error details:', error);
    
    // Return appropriate error response
    return NextResponse.json(
      { 
        error: error.message || 'Internal server error',
        code: error.code || 'unknown'
      },
      { status: 500 }
    );
  }
}