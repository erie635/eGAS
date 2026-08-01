import { NextResponse } from 'next/server';

const GOOGLE_API_KEY = 'AIzaSyATIUosv_VCeiVsQ3q6_LSQhZkrHr0E79o';

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const origin = searchParams.get('origin');
  const destination = searchParams.get('destination');
  const alternatives = searchParams.get('alternatives') === 'true';
  
  if (!origin || !destination) {
    return NextResponse.json(
      { error: 'Missing origin or destination' },
      { status: 400 }
    );
  }

  try {
    let url = `https://maps.googleapis.com/maps/api/directions/json?origin=${origin}&destination=${destination}&key=${GOOGLE_API_KEY}&departure_time=now&traffic_model=best_guess`;
    
    if (alternatives) {
      url += '&alternatives=true';
    }

    const response = await fetch(url);
    const data = await response.json();
    
    return NextResponse.json(data);
  } catch (error) {
    return NextResponse.json(
      { error: 'Failed to fetch directions' },
      { status: 500 }
    );
  }
}