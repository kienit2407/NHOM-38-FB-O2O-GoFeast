import {
    Body,
    Controller,
    Delete,
    Get,
    Param,
    Patch,
    Query,
    Req,
    UseGuards,
} from '@nestjs/common';
import { Client } from 'src/modules/auth/decorators/client.decorator';
import { JwtAuthGuard } from 'src/modules/auth/guards/jwt-auth.guard';
import { OptionalJwtAuthGuard } from 'src/modules/auth/guards';
import { ListNotificationsDto } from '../dtos/list-notifications.dto';
import { NotificationsService } from '../services/notifications.service';

@Controller('notifications')
export class NotificationsController {
    constructor(private readonly notificationsService: NotificationsService) { }

    @Get('me')
    @UseGuards(JwtAuthGuard)
    async listMine(@Req() req: any, @Query() query: ListNotificationsDto) {
        const data = await this.notificationsService.listMine(
            req.user.userId,
            query.page ?? 1,
            query.limit ?? 20,
            {
                excludePromotion: query.exclude_promotion === true,
                role: req.user.role,
            },
        );
        return { success: true, data };
    }

    @Get('me/unread-count')
    @UseGuards(JwtAuthGuard)
    async unreadCount(@Req() req: any, @Query() query: ListNotificationsDto) {
        const data = await this.notificationsService.getUnreadCount(
            req.user.userId,
            {
                excludePromotion: query.exclude_promotion === true,
                role: req.user.role,
            },
        );
        return { success: true, data };
    }
    @Patch('me/read-all')
    @UseGuards(JwtAuthGuard)
    async markAllRead(@Req() req: any) {
        const data = await this.notificationsService.markAllRead(
            req.user.userId,
            req.user.role,
        );
        return { success: true, data };
    }
    @Delete('me/clear-all')
    @UseGuards(JwtAuthGuard)
    async clearAllMine(@Req() req: any) {
        const data = await this.notificationsService.clearAll(
            req.user.userId,
            req.user.role,
        );
        return { success: true, data };
    }

    @Delete('me/:id')
    @UseGuards(JwtAuthGuard)
    async removeMine(@Req() req: any, @Param('id') id: string) {
        const data = await this.notificationsService.removeOne(
            req.user.userId,
            id,
            req.user.role,
        );
        return { success: true, data };
    }
    @Patch('me/:id/read')
    @UseGuards(JwtAuthGuard)
    async markRead(@Req() req: any, @Param('id') id: string) {
        const data = await this.notificationsService.markRead(
            req.user.userId,
            id,
            req.user.role,
        );
        return { success: true, data };
    }
}
