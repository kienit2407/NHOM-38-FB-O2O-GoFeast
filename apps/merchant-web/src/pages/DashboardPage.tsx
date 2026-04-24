/* eslint-disable @typescript-eslint/no-explicit-any */
import {
  ArrowRight,
  TrendingUp,
  TrendingDown,
  ShoppingBag,
  DollarSign,
  Star,
  Clock,
  ChefHat,
  AlertTriangle,
} from "lucide-react";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { useMerchantAuth } from "@/store/authStore";
import { Link } from "react-router-dom";
import { useEffect, useMemo } from "react";
import { useMerchantOrderStore } from "@/store/merchantOrderStore";
import { useMerchantStatisticsStore } from "@/store/merchantStatisticsStore";
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
} from "recharts";
import { useMerchantSocketStore } from "@/store/merchantSocketStore";

const formatCurrency = (value: number) => {
  return new Intl.NumberFormat("vi-VN", {
    style: "currency",
    currency: "VND",
    maximumFractionDigits: 0,
  }).format(value || 0);
};

const orderTypeLabel = (v: string) =>
  v === "delivery" ? "Giao hàng" : "Tại quán";

const orderStatusLabel = (v: string, orderType?: string) => {
  switch (v) {
    case "pending":
      return "Mới";
    case "confirmed":
      return "Đã xác nhận";
    case "preparing":
      return "Đang chuẩn bị";
    case "ready_for_pickup":
      return orderType === "dine_in" ? "Sẵn sàng phục vụ" : "Sẵn sàng lấy";
    case "driver_assigned":
      return "Đã có tài xế";
    case "driver_arrived":
      return "Tài xế đã tới";
    case "picked_up":
      return "Đã lấy món";
    case "delivering":
      return "Đang giao";
    case "delivered":
      return "Đã giao";
    case "completed":
      return "Hoàn thành";
    case "cancelled":
      return "Đã huỷ";
    default:
      return v;
  }
};

const formatShortCurrency = (value: number) => {
  if (value >= 1_000_000) return `${(value / 1_000_000).toFixed(1)}M`;
  if (value >= 1_000) return `${(value / 1_000).toFixed(0)}K`;
  return String(value || 0);
};

const chartLabel = (value: string) =>
  new Date(value).toLocaleDateString("vi-VN", {
    day: "2-digit",
    month: "2-digit",
  });

export default function DashboardPage() {
  const { user } = useMerchantAuth();

  const items = useMerchantOrderStore((s) => s.items);
  const fetchOrders = useMerchantOrderStore((s) => s.fetchOrders);

  const dashboard = useMerchantStatisticsStore((s) => s.dashboard);
  const loadingDashboard = useMerchantStatisticsStore((s) => s.loadingDashboard);
  const errorDashboard = useMerchantStatisticsStore((s) => s.errorDashboard);
  const fetchDashboard = useMerchantStatisticsStore((s) => s.fetchDashboard);
  const socketOrdersMap = useMerchantSocketStore((s) => s.ordersMap);
  const lastSocketEventAt = useMerchantSocketStore((s) => s.lastEventAt);
  useEffect(() => {
    void fetchDashboard();
    void fetchOrders();
  }, [fetchDashboard, fetchOrders]);

  useEffect(() => {
    if (!lastSocketEventAt) return;

    const t = setTimeout(() => {
      void fetchDashboard();
      void fetchOrders();
    }, 200);

    return () => clearTimeout(t);
  }, [lastSocketEventAt, fetchDashboard, fetchOrders]);
  const storeName =
    (user as any)?.merchant?.name ||
    (user as any)?.merchant?.store_name ||
    (user as any)?.store_name ||
    "quán";

  const getUserName = () => {
    if (!user) return "";
    return (
      (user as any).full_name ||
      (user as any).name ||
      user.email ||
      "Merchant"
    );
  };

  const summary = dashboard?.summary;
  const bestSellers = dashboard?.best_sellers ?? [];
  const recentOrders = items.slice(0, 5);

  const revenueChart = useMemo(() => {
    const raw =
      (dashboard as any)?.revenueChart ??
      (dashboard as any)?.revenue_chart ??
      (dashboard as any)?.chart ??
      [];

    if (!Array.isArray(raw)) return [];

    return raw
      .map((x: any) => ({
        date: x?.date ?? x?.day ?? x?.label ?? null,
        revenue: Number(x?.revenue ?? 0),
        gross_revenue: Number(x?.gross_revenue ?? 0),
        orders: Number(x?.orders ?? x?.order_count ?? 0),
      }))
      .filter((x: any) => x.date);
  }, [dashboard]);
  const livePendingCount = useMemo(
    () =>
      Object.values(socketOrdersMap).filter((x) => x.status === "pending").length,
    [socketOrdersMap],
  );

  const livePreparingCount = useMemo(
    () =>
      Object.values(socketOrdersMap).filter((x) =>
        ["confirmed", "preparing", "ready_for_pickup"].includes(x.status ?? ""),
      ).length,
    [socketOrdersMap],
  );
  const todayRevenue = summary?.today_revenue ?? 0;
  const revenueChange = summary?.revenue_change_pct ?? 0;
  const newOrders = Math.max(summary?.new_orders ?? 0, livePendingCount);
  const preparingOrders = Math.max(
    summary?.preparing_orders ?? 0,
    livePreparingCount,
  );
  const avgRating = Number(summary?.average_rating ?? 0).toFixed(1);
  const totalReviews = summary?.total_reviews ?? 0;
  const prepTime =
    Number(
      summary?.average_prep_time_min ??
      (user as any)?.merchant?.average_prep_time_min ??
      0,
    ) || 0;

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex flex-col gap-2">
        <h1 className="text-2xl font-bold">Xin chào, {getUserName()} 👋</h1>
        <p className="text-muted-foreground">
          Đây là tổng quan hoạt động của {storeName} hôm nay.
        </p>
      </div>

      {errorDashboard && (
        <Card className="border-destructive bg-destructive/5">
          <CardContent className="py-4 text-sm text-destructive">
            {errorDashboard}
          </CardContent>
        </Card>
      )}

      {newOrders > 0 && (
        <Card className="border-warning bg-warning/5">
          <CardContent className="flex items-center gap-4 py-4">
            <div className="w-10 h-10 rounded-full bg-warning/20 flex items-center justify-center animate-pulse-ring">
              <AlertTriangle className="w-5 h-5 text-warning" />
            </div>
            <div className="flex-1">
              <p className="font-medium">
                Bạn có {newOrders} đơn hàng mới đang chờ xác nhận!
              </p>
              <p className="text-sm text-muted-foreground">
                Xác nhận ngay để đảm bảo SLA
              </p>
            </div>
            <Button asChild>
              <Link to="/app/orders/delivery">
                Xem đơn hàng
                <ArrowRight className="w-4 h-4 ml-2" />
              </Link>
            </Button>
          </CardContent>
        </Card>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <Card className="hover:shadow-card-hover transition-shadow">
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-muted-foreground">Doanh thu hôm nay</p>
                <p className="text-2xl font-bold mt-1">
                  {loadingDashboard ? "..." : formatCurrency(todayRevenue)}
                </p>
                <div className="flex items-center gap-1 mt-1">
                  {Number(revenueChange) >= 0 ? (
                    <TrendingUp className="w-4 h-4 text-success" />
                  ) : (
                    <TrendingDown className="w-4 h-4 text-destructive" />
                  )}
                  <span
                    className={`text-sm ${Number(revenueChange) >= 0
                      ? "text-success"
                      : "text-destructive"
                      }`}
                  >
                    {revenueChange}%
                  </span>
                  <span className="text-xs text-muted-foreground">
                    so với hôm qua
                  </span>
                </div>
              </div>
              <div className="w-12 h-12 rounded-full bg-primary/10 flex items-center justify-center">
                <DollarSign className="w-6 h-6 text-primary" />
              </div>
            </div>
          </CardContent>
        </Card>

        <Card className="hover:shadow-card-hover transition-shadow">
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-muted-foreground">Đơn hàng mới</p>
                <p className="text-2xl font-bold mt-1">{newOrders}</p>
                <p className="text-sm text-muted-foreground mt-1">
                  <span className="text-warning font-medium">
                    {preparingOrders}
                  </span>{" "}
                  đang chuẩn bị
                </p>
              </div>
              <div className="w-12 h-12 rounded-full bg-accent/10 flex items-center justify-center">
                <ShoppingBag className="w-6 h-6 text-accent" />
              </div>
            </div>
          </CardContent>
        </Card>

        <Card className="hover:shadow-card-hover transition-shadow">
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-muted-foreground">
                  Đánh giá trung bình
                </p>
                <p className="text-2xl font-bold mt-1 flex items-center gap-1">
                  {avgRating}
                  <Star className="w-5 h-5 text-warning fill-warning" />
                </p>
                <p className="text-sm text-muted-foreground mt-1">
                  {totalReviews} đánh giá
                </p>
              </div>
              <div className="w-12 h-12 rounded-full bg-warning/10 flex items-center justify-center">
                <Star className="w-6 h-6 text-warning" />
              </div>
            </div>
          </CardContent>
        </Card>

        <Card className="hover:shadow-card-hover transition-shadow">
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-muted-foreground">
                  Thời gian chuẩn bị TB
                </p>
                <p className="text-2xl font-bold mt-1">{prepTime} phút</p>
                <p className="text-sm text-success mt-1">Dữ liệu từ merchant</p>
              </div>
              <div className="w-12 h-12 rounded-full bg-success/10 flex items-center justify-center">
                <Clock className="w-6 h-6 text-success" />
              </div>
            </div>
          </CardContent>
        </Card>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <Card className="lg:col-span-2">
          <CardHeader>
            <CardTitle>Doanh thu 7 ngày gần nhất</CardTitle>
            <CardDescription>Theo dõi doanh thu theo ngày</CardDescription>
          </CardHeader>
          <CardContent>
            <div className="h-[300px]">
              {revenueChart.length === 0 ? (
                <div className="flex h-full items-center justify-center rounded-md border border-dashed text-sm text-muted-foreground">
                  Chưa có dữ liệu biểu đồ
                </div>
              ) : (
                <ResponsiveContainer width="100%" height="100%">
                  <LineChart data={revenueChart}>
                    <CartesianGrid strokeDasharray="3 3" />
                    <XAxis
                      dataKey="date"
                      tickFormatter={chartLabel}
                      tick={{ fontSize: 12 }}
                    />
                    <YAxis
                      tickFormatter={formatShortCurrency}
                      tick={{ fontSize: 12 }}
                    />
                    <Tooltip
                      formatter={(value: number) => formatCurrency(value)}
                      labelFormatter={(value) =>
                        new Date(value).toLocaleDateString("vi-VN")
                      }
                      contentStyle={{
                        backgroundColor: "hsl(var(--card))",
                        border: "1px solid hsl(var(--border))",
                        borderRadius: "8px",
                      }}
                    />
                    <Line
                      type="monotone"
                      dataKey="revenue"
                      stroke="hsl(var(--primary))"
                      strokeWidth={3}
                      dot={{ r: 4 }}
                      activeDot={{ r: 6 }}
                    />
                  </LineChart>
                </ResponsiveContainer>
              )}
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader>
            <div className="flex items-center justify-between">
              <CardTitle>Món bán chạy</CardTitle>
              <Button variant="ghost" size="sm" asChild>
                <Link to="/app/reports/best-sellers">Xem tất cả</Link>
              </Button>
            </div>
          </CardHeader>
          <CardContent className="space-y-4">
            {bestSellers.length === 0 ? (
              <p className="text-sm text-muted-foreground">
                Chưa có dữ liệu món bán chạy
              </p>
            ) : (
              bestSellers.slice(0, 5).map((item, index) => (
                <div key={item.product_id} className="flex items-center gap-3">
                  <div
                    className={`w-8 h-8 rounded-full flex items-center justify-center text-sm font-medium
                    ${index === 0
                        ? "bg-warning/20 text-warning"
                        : index === 1
                          ? "bg-muted text-muted-foreground"
                          : index === 2
                            ? "bg-orange-100 text-orange-600"
                            : "bg-muted text-muted-foreground"
                      }`}
                  >
                    {index + 1}
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="font-medium truncate">{item.product_name}</p>
                    <p className="text-sm text-muted-foreground">
                      {item.quantity} đã bán
                    </p>
                  </div>
                  <p className="font-medium text-sm">
                    {formatShortCurrency(item.revenue)}
                  </p>
                </div>
              ))
            )}
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <div>
              <CardTitle>Đơn hàng gần đây</CardTitle>
              <CardDescription>Theo dõi trạng thái đơn hàng</CardDescription>
            </div>
            <Button asChild>
              <Link to="/app/orders/delivery">
                Xem tất cả
                <ArrowRight className="w-4 h-4 ml-2" />
              </Link>
            </Button>
          </div>
        </CardHeader>
        <CardContent>
          <div className="space-y-4">
            {recentOrders.length === 0 ? (
              <p className="text-sm text-muted-foreground">
                Chưa có đơn hàng gần đây
              </p>
            ) : (
              recentOrders.map((order) => (
                <div
                  key={order.id}
                  className="flex items-center gap-4 p-3 rounded-lg bg-muted/50 hover:bg-muted transition-colors"
                >
                  <div className="w-10 h-10 rounded-full bg-card flex items-center justify-center">
                    {order.order_type === "delivery" ? (
                      <ShoppingBag className="w-5 h-5 text-primary" />
                    ) : (
                      <ChefHat className="w-5 h-5 text-accent" />
                    )}
                  </div>

                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                      <p className="font-medium">#{order.order_number}</p>
                      <Badge
                        variant={
                          order.order_type === "delivery"
                            ? "default"
                            : "secondary"
                        }
                      >
                        {orderTypeLabel(order.order_type)}
                      </Badge>
                    </div>
                    <p className="text-sm text-muted-foreground truncate">
                      {order.items
                        .map((i) => `${i.quantity}x ${i.name}`)
                        .join(", ")}
                    </p>
                  </div>

                  <div className="text-right">
                    <p className="font-medium">
                      {formatCurrency(order.total_amount)}
                    </p>
                    <Badge variant="outline">
                      {orderStatusLabel(order.status, order.order_type)}
                    </Badge>
                  </div>
                </div>
              ))
            )}
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
