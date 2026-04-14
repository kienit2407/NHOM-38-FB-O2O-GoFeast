import {
    Body,
    Controller,
    Get,
    Param,
    Patch,
    Query,
    Req,
    UseGuards,
} from '@nestjs/common';

import { JwtAuthGuard } from 'src/modules/auth/guards/jwt-auth.guard';
import { RolesGuard } from 'src/modules/auth/guards/roles.guard';
import { Roles } from 'src/modules/auth/decorators/roles.decorator';

import { AdminDashboardQueryDto } from '../dtos/admin-dashboard-query.dto';
import { AdminOrdersQueryDto } from '../dtos/admin-orders-query.dto';
import { AdminForceCancelOrderDto } from '../dtos/admin-force-cancel-order.dto';
import { AdminGlobalSearchQueryDto } from '../dtos/admin-global-search-query.dto';
import { AdminOpsService } from '../services/admin-ops.service';

@Controller('admin')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('admin')
export class AdminOpsController {
    constructor(private readonly adminOpsService: AdminOpsService) { }

    @Get('dashboard/summary')
    async dashboardSummary(@Query() query: AdminDashboardQueryDto) {
        const data = await this.adminOpsService.getDashboardSummary(query);
        return { success: true, data };
    }

    @Get('orders')
    async listOrders(@Query() query: AdminOrdersQueryDto) {
        const data = await this.adminOpsService.getOrders(query);
        return { success: true, data };
    }

    @Get('orders/:id')
    async orderDetail(@Param('id') orderId: string) {
        const data = await this.adminOpsService.getOrderDetail(orderId);
        return { success: true, data };
    }

    @Patch('orders/:id/force-cancel')
    async forceCancelOrder(
        @Req() req: any,
        @Param('id') orderId: string,
        @Body() body: AdminForceCancelOrderDto,
    ) {
        const adminUserId = String(req.user?.userId ?? req.user?.sub ?? '');
        const data = await this.adminOpsService.forceCancelOrder(
            adminUserId,
            orderId,
            body.reason,
        );

        return { success: true, data };
    }

    @Get('search/global')
    async searchGlobal(@Query() query: AdminGlobalSearchQueryDto) {
        const data = await this.adminOpsService.searchGlobal(query);
        return { success: true, data };
    }
}
