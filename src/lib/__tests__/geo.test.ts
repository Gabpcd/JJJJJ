import { describe, it, expect } from 'vitest';
import { calculerDistanceKm, formaterDistance } from '../geo';

describe('calculerDistanceKm', () => {
  it('should return null when any coordinate is null', () => {
    expect(calculerDistanceKm(null, 2.35, 48.86, 2.35)).toBeNull();
    expect(calculerDistanceKm(48.86, null, 48.86, 2.35)).toBeNull();
    expect(calculerDistanceKm(48.86, 2.35, null, 2.35)).toBeNull();
    expect(calculerDistanceKm(48.86, 2.35, 48.86, null)).toBeNull();
  });

  it('should return 0 for same point', () => {
    expect(calculerDistanceKm(48.8566, 2.3522, 48.8566, 2.3522)).toBe(0);
  });

  it('should calculate Paris to Lyon (~390-395 km)', () => {
    const d = calculerDistanceKm(48.8566, 2.3522, 45.7640, 4.8357);
    expect(d).toBeGreaterThan(385);
    expect(d).toBeLessThan(400);
  });

  it('should calculate Paris to Marseille (~660-670 km)', () => {
    const d = calculerDistanceKm(48.8566, 2.3522, 43.2965, 5.3698);
    expect(d).toBeGreaterThan(655);
    expect(d).toBeLessThan(675);
  });

  it('should calculate short distance (< 1km)', () => {
    // Two points ~500m apart in Paris
    const d = calculerDistanceKm(48.8566, 2.3522, 48.8610, 2.3522);
    expect(d).toBeGreaterThan(0);
    expect(d).toBeLessThan(1);
  });
});

describe('formaterDistance', () => {
  it('should return "Distance inconnue" for null', () => {
    expect(formaterDistance(null)).toBe('Distance inconnue');
  });

  it('should format meters for < 1km', () => {
    expect(formaterDistance(0.5)).toBe('500m');
    expect(formaterDistance(0.15)).toBe('150m');
  });

  it('should format km for >= 1km', () => {
    expect(formaterDistance(5.2)).toBe('5.2 km');
    expect(formaterDistance(100)).toBe('100 km');
  });
});
