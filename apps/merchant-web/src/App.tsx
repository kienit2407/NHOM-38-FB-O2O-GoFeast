import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Routes, Route, Navigate, Outlet } from "react-router-dom";
import { useEffect, useState } from "react";
import { DashboardLayout } from "@/components/layout/DashboardLayout";
import { useMerchantAuth } from "@/store/authStore";

// Landing & Auth Pages
import LandingPage from "@/pages/landing/LandingPage";
import MerchantRegisterPage from "@/pages/landing/MerchantRegisterPage";
import WaitingApprovalPage from "@/pages/landing/WaitingApprovalPage";
import LoginPage from "@/pages/LoginPage";
import ForgotPasswordPage from "@/pages/ForgotPasswordPage";

// Dashboard Pages
import DashboardPage from "@/pages/DashboardPage";
import OrdersPage from "@/pages/orders/OrdersPage";
import CategoriesPage from "@/pages/menu/CategoriesPage";
import ProductsPage from "@/pages/menu/ProductsPage";
import ToppingsPage from "@/pages/menu/ToppingsPage";
import OptionsPage from "@/pages/menu/OptionsPage";
import PromotionsPage from "@/pages/PromotionsPage";
import BranchesPage from "@/pages/BranchesPage";
import TeamPage from "@/pages/TeamPage";
import RevenueReportPage from "@/pages/reports/RevenueReportPage";
import BestSellersPage from "@/pages/reports/BestSellersPage";
import ReviewsPage from "@/pages/reports/ReviewsPage";
import SettingsPage from "@/pages/SettingsPage";
import AuditLogsPage from "@/pages/AuditLogsPage";
import NotFound from "@/pages/NotFound";
import VouchersPage from "./pages/VouchersPage";
import TablesPage from "./pages/TablesPage";
import { useMerchantSocketBootstrap } from "./hooks/use-merchant-socket-bootstrap";

const queryClient = new QueryClient();

function FullscreenSpinner() {
  return (
    <div className="min-h-screen flex items-center justify-center">
      <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-orange-500" />
    </div>
  );
}
function AuthPagesGate() {
  const { accessToken, onboarding, bootstrap } = useMerchantAuth();
  const [ready, setReady] = useState(false);

  useEffect(() => {
    (async () => {
      try { await bootstrap(); } finally { setReady(true); }
    })();
  }, [bootstrap]);

  if (!ready) return <FullscreenSpinner />;

  if (!accessToken) return <Outlet />;

  const status = onboarding?.merchant_approval_status;
  const step = onboarding?.current_step;

  if (status === "approved") return <Navigate to="/app/dashboard" replace />;
  if (status === "pending_approval" || step === "waiting_approval") return <Navigate to="/merchant/status" replace />;

  // logged in nhưng chưa approved -> cho về register để hoàn tất
  return <Navigate to="/merchant/register" replace />;
}
function MerchantRegisterGate() {
  const { accessToken, onboarding, bootstrap } = useMerchantAuth();
  const [ready, setReady] = useState(false);

  useEffect(() => {
    (async () => {
      try { await bootstrap(); } finally { setReady(true); }
    })();
  }, [bootstrap]);

  if (!ready) return <FullscreenSpinner />;

  const status = onboarding?.merchant_approval_status;
  const step = onboarding?.current_step;

  // approved -> vào app
  if (accessToken && status === "approved") return <Navigate to="/app/dashboard" replace />;

  // pending -> về status (hoặc landing tuỳ rule của bạn)
  if (accessToken && (status === "pending_approval" || step === "waiting_approval")) {
    return <Navigate to="/merchant/status" replace />;
  }

  // rejected/draft/... => CHO VÀO register để sửa/hoàn tất
  return <MerchantRegisterPage />;
}

/**
 * ProtectedRoute
 * - chỉ cho vào /app/*
 * - nếu chưa login -> về /login
 * - nếu pending -> về / (Landing)
 * - nếu onboarding dở -> về /merchant/register
 * - nếu approved -> OK
 */
function ProtectedRoute() {
  const { accessToken, onboarding, bootstrap } = useMerchantAuth();
  const [isChecking, setIsChecking] = useState(true);
  const [hasBootstrapped, setHasBootstrapped] = useState(false);

  useEffect(() => {
    // Prevent multiple bootstrap calls
    if (hasBootstrapped) {
      setIsChecking(false);
      return;
    }

    const run = async () => {
      try {
        await bootstrap();
      } finally {
        setIsChecking(false);
        setHasBootstrapped(true);
      }
    };
    run();
  }, [bootstrap, hasBootstrapped]);

  if (isChecking) return <FullscreenSpinner />;

  // chưa login
  if (!accessToken) return <Navigate to="/login" replace />;

  const status = onboarding?.merchant_approval_status;
  const step = onboarding?.current_step;

  // approved -> cho vào dashboard
  if (status === "approved") return <Outlet />;

  // pending/waiting -> về landing (rule bạn muốn)
  if (status === "pending_approval" || step === "waiting_approval") {
    return <Navigate to="/" replace />;
  }

  // rejected -> cho phép vào register để chỉnh sửa
  if (status === "rejected") {
    return <Outlet />;
  }

  // onboarding dở -> về register
  if (onboarding?.has_onboarding && onboarding?.current_step !== "approved") {
    // (nếu bạn có is_completed thì check thêm, còn không thì cứ dựa step)
    return <Navigate to="/merchant/register" replace />;
  }

  return <Navigate to="/merchant/register" replace />;
}

/**
 * PublicOnlyRoute
 * - chỉ cho vào /login /forgot-password /merchant/register khi CHƯA approved
 * - nếu approved -> /app/dashboard
 * - nếu pending -> / (Landing)
 * - nếu đã login nhưng onboarding dở -> vẫn cho vào /merchant/register
 */
function PublicOnlyRoute() {
  const { accessToken, onboarding, bootstrap } = useMerchantAuth();
  const [isChecking, setIsChecking] = useState(true);
  const [hasBootstrapped, setHasBootstrapped] = useState(false);

  useEffect(() => {
    // Prevent multiple bootstrap calls
    if (hasBootstrapped) {
      setIsChecking(false);
      return;
    }

    const run = async () => {
      try {
        await bootstrap();
      } finally {
        setIsChecking(false);
        setHasBootstrapped(true);
      }
    };
    run();
  }, [bootstrap, hasBootstrapped]);

  if (isChecking) return <FullscreenSpinner />;

  if (!accessToken) {
    // chưa login -> ok vào public pages
    return <Outlet />;
  }

  const status = onboarding?.merchant_approval_status;
  const step = onboarding?.current_step;

  if (status === "approved") return <Navigate to="/app/dashboard" replace />;

  // pending -> về landing
  if (status === "pending_approval" || step === "waiting_approval") {
    return <Navigate to="/" replace />;
  }

  // rejected -> cho phép vào register để chỉnh sửa
  if (status === "rejected") {
    return <Navigate to="/merchant/register" replace />;
  }

  // onboarding dở -> cho phép vào register (Outlet)
  return <Outlet />;
}

/**
 * LandingRedirectGate (optional)
 * - nếu user đã approved mà vào / thì tự đẩy sang dashboard
 * - pending thì ở lại landing
 */
function LandingGate({ children }: { children: React.ReactNode }) {
  const { accessToken, onboarding, bootstrap } = useMerchantAuth();
  const [ready, setReady] = useState(false);
  const [hasBootstrapped, setHasBootstrapped] = useState(false);

  useEffect(() => {
    // Prevent multiple bootstrap calls
    if (hasBootstrapped) {
      setReady(true);
      return;
    }

    const run = async () => {
      try {
        await bootstrap();
      } finally {
        setReady(true);
        setHasBootstrapped(true);
      }
    };
    run();
  }, [bootstrap, hasBootstrapped]);

  if (!ready) return <FullscreenSpinner />;

  if (accessToken && onboarding?.merchant_approval_status === "approved") {
    return <Navigate to="/app/dashboard" replace />;
  }

  return <>{children}</>;
}

export default function App() {
  useMerchantSocketBootstrap();

  return (
    <QueryClientProvider client={queryClient}>
      <TooltipProvider>
        <Toaster />
        <Sonner />
        <BrowserRouter>
          <Routes>
            {/* Landing public - nhưng nếu approved thì auto redirect */}
            <Route path="/" element={<LandingGate><LandingPage /></LandingGate>} />

            <Route element={<AuthPagesGate />}>
              <Route path="/login" element={<LoginPage />} />
              <Route path="/forgot-password" element={<ForgotPasswordPage />} />
            </Route>

            <Route path="/merchant/register" element={<MerchantRegisterGate />} />

            {/* Status page: nếu bạn vẫn muốn giữ để xem trạng thái thì OK.
                Nhưng rule của bạn là pending về landing, nên trang này nên chỉ là optional. */}
            <Route path="/merchant/status" element={<WaitingApprovalPage />} />
            <Route path="/merchant/waiting" element={<WaitingApprovalPage />} />

            <Route element={<ProtectedRoute />}>
              <Route path="/app" element={<DashboardLayout />}>
                <Route index element={<Navigate to="/app/dashboard" replace />} />
                <Route path="dashboard" element={<DashboardPage />} />

                <Route path="orders/delivery" element={<OrdersPage />} />
                <Route path="orders/dine-in" element={<OrdersPage />} />
                <Route path="/app/dine-in/tables" element={<TablesPage />} />
                <Route path="menu/categories" element={<CategoriesPage />} />
                <Route path="menu/products" element={<ProductsPage />} />
                <Route path="menu/toppings" element={<ToppingsPage />} />
                <Route path="menu/options" element={<OptionsPage />} />

                <Route path="promotions/promotion" element={<PromotionsPage />} />
                <Route path="promotions/voucher" element={<VouchersPage />} />
                <Route path="branches" element={<BranchesPage />} />
                <Route path="team" element={<TeamPage />} />

                <Route path="reports/revenue" element={<RevenueReportPage />} />
                <Route path="reports/best-sellers" element={<BestSellersPage />} />
                <Route path="reports/reviews" element={<ReviewsPage />} />

                <Route path="settings" element={<SettingsPage />} />
                <Route path="audit-logs" element={<AuditLogsPage />} />
              </Route>
            </Route>

            <Route path="*" element={<NotFound />} />
          </Routes>
        </BrowserRouter>
      </TooltipProvider>
    </QueryClientProvider>
  );
}
