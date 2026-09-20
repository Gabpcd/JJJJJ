import React, { Suspense, lazy } from 'react';
import { act, cleanup, render } from '@testing-library/react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { MemoryRouter, Navigate, Route, Routes } from 'react-router-dom';
import { NativeUpdateReady } from './NativeUpdateReady';
import { ChargementPage } from './ChargementPage';

const prepare = vi.hoisted(() => vi.fn().mockResolvedValue(undefined));
vi.mock('@/lib/mobileUpdates', () => ({ prepareMobileUpdate: prepare }));
vi.mock('@capacitor/core', () => ({ Capacitor: { isNativePlatform: () => true } }));
beforeEach(() => { prepare.mockClear(); vi.useFakeTimers(); });
afterEach(() => { cleanup(); vi.useRealTimers(); });
async function frames() { await act(async () => { await vi.advanceTimersByTimeAsync(80); }); }

it('waits through guard loading, redirects and lazy route resolution before acknowledging startup', async () => {
  let resolve!: (value: { default: React.ComponentType }) => void;
  const Dashboard = lazy(() => new Promise<{ default: React.ComponentType }>(r => { resolve = r; }));
  function Harness({ loading }: { loading: boolean }) {
    return <MemoryRouter><Suspense fallback={<ChargementPage />}>
      <Routes>
        <Route path="/" element={loading ? <ChargementPage /> : <Navigate to="/dashboard" replace />} />
        <Route path="/dashboard" element={<Dashboard />} />
      </Routes><NativeUpdateReady />
    </Suspense></MemoryRouter>;
  }
  const view = render(<Harness loading />);
  await frames(); expect(prepare).not.toHaveBeenCalled();
  view.rerender(<Harness loading={false} />);
  await frames(); expect(prepare).not.toHaveBeenCalled();
  await act(async () => resolve({ default: () => <main>Dashboard prêt</main> }));
  await frames(); expect(prepare).toHaveBeenCalledOnce();
});

it('never acknowledges a lazy route that crashes during initial render', async () => {
  class Boundary extends React.Component<React.PropsWithChildren, { failed: boolean }> {
    state = { failed: false };
    static getDerivedStateFromError() { return { failed: true }; }
    render() { return this.state.failed ? <div>Erreur</div> : this.props.children; }
  }
  const error = vi.spyOn(console, 'error').mockImplementation(() => {});
  const Broken = lazy(async () => ({ default: () => { throw new Error('Broken bundle'); } }));
  render(<Boundary><MemoryRouter><Suspense fallback={<ChargementPage />}><Broken /><NativeUpdateReady /></Suspense></MemoryRouter></Boundary>);
  await frames(); expect(prepare).not.toHaveBeenCalled();
  error.mockRestore();
});
