import { createContext, useContext, type ReactNode } from 'react';

const AdminInterfaceContext = createContext(false);

export function AdminInterfaceProvider({ children }: { children: ReactNode }) {
  return (
    <AdminInterfaceContext.Provider value>
      {children}
    </AdminInterfaceContext.Provider>
  );
}

// Hook colocated with its private context so consumers cannot bypass the provider API.
// eslint-disable-next-line react-refresh/only-export-components
export function useAdminInterface(): boolean {
  return useContext(AdminInterfaceContext);
}
