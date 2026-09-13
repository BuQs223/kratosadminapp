import { useInfiniteQuery, useQuery } from '@tanstack/react-query';
import { router, Stack } from 'expo-router';
import React from 'react';
import {
  ActivityIndicator,
  FlatList,
  Pressable,
  StyleSheet,
  TextInput,
  View,
} from 'react-native';

import { AppText } from '@/components/app-text';
import { ManualRefreshControl } from '@/components/manual-refresh-control';
import { MaterialIcon } from '@/components/material-icon';
import { getMembersPage, type MemberFilters } from '@/repositories/members-repository';
import { lookupsRepository } from '@/repositories/lookups-repository';
import { MemberCard } from '@/screens/members/member-card';
import {
  MembersFilterSheet,
  type AppliedMemberFilters,
} from '@/screens/members/members-filter-sheet';
import { colorWithAlpha, useAppTheme } from '@/theme/theme';

const pageSize = 20;
const defaultFilters: AppliedMemberFilters = {
  membershipStatus: 'all',
  frozenStatus: 'all',
};

export default function MembersScreen() {
  const { colors } = useAppTheme();
  const [searchInput, setSearchInput] = React.useState('');
  const [searchQuery, setSearchQuery] = React.useState('');
  const [filters, setFilters] = React.useState<AppliedMemberFilters>(defaultFilters);
  const [filtersVisible, setFiltersVisible] = React.useState(false);

  React.useEffect(() => {
    const timeout = setTimeout(() => setSearchQuery(searchInput), 500);
    return () => clearTimeout(timeout);
  }, [searchInput]);

  const appliedFilters = React.useMemo<MemberFilters>(
    () => ({ ...filters, search: searchQuery }),
    [filters, searchQuery],
  );

  const membersQuery = useInfiniteQuery({
    queryKey: ['members', appliedFilters],
    queryFn: ({ pageParam }) =>
      getMembersPage({ filters: appliedFilters, limit: pageSize, offset: pageParam }),
    initialPageParam: 0,
    getNextPageParam: (lastPage, pages) =>
      lastPage.hasMore
        ? pages.reduce((total, page) => total + page.items.length, 0)
        : undefined,
  });
  const lookupsQuery = useQuery({
    queryKey: ['member-filter-lookups'],
    queryFn: async () => {
      const [gyms, plans] = await Promise.all([
        lookupsRepository.getGyms(),
        lookupsRepository.getActiveMembershipPlans(),
      ]);
      return { gyms, plans };
    },
    staleTime: 5 * 60_000,
  });

  const members = membersQuery.data?.pages.flatMap((page) => page.items) ?? [];
  const totalCount = membersQuery.data?.pages[0]?.totalCount ?? 0;
  const activeFiltersCount = countActiveFilters(filters);

  return (
    <View style={[styles.screen, { backgroundColor: colors.surfaceContainerLowest }]}>
      <Stack.Screen
        options={{
          title: 'Membri',
          headerRight: () => (
            <View style={styles.headerActions}>
              <Pressable
                accessibilityRole="button"
                accessibilityLabel="Analiză Gold Check-ins"
                onPress={() => router.push('/gold-checkins')}
                hitSlop={10}
                style={({ pressed }) => ({ opacity: pressed ? 0.55 : 1, padding: 6 })}>
                <MaterialIcon name="analytics_outlined" size={24} color={colors.onSurfaceVariant} />
              </Pressable>
              <Pressable
                accessibilityRole="button"
                accessibilityLabel="Filtre"
                onPress={() => setFiltersVisible(true)}
                hitSlop={10}
                style={({ pressed }) => [styles.filterAction, { opacity: pressed ? 0.55 : 1 }]}>
                <MaterialIcon name="filter_list" size={24} color={colors.onSurfaceVariant} />
                {activeFiltersCount > 0 ? (
                  <View style={[styles.filterCount, { backgroundColor: colors.error }]}>
                    <AppText color="#FFFFFF" style={styles.filterCountText}>
                      {activeFiltersCount}
                    </AppText>
                  </View>
                ) : null}
              </Pressable>
            </View>
          ),
        }}
      />

      <View style={styles.searchArea}>
        <View style={[styles.searchField, { borderColor: colors.outline }]}>
          <MaterialIcon name="search" size={24} color={colors.onSurfaceVariant} />
          <TextInput
            accessibilityLabel="Caută membri"
            value={searchInput}
            onChangeText={setSearchInput}
            placeholder="Caută după nume, telefon, email sau ID..."
            placeholderTextColor={colors.onSurfaceVariant}
            selectionColor={colors.primary}
            autoCapitalize="none"
            autoCorrect={false}
            style={[styles.searchInput, { color: colors.onSurface }]}
          />
          {searchInput ? (
            <Pressable
              accessibilityRole="button"
              accessibilityLabel="Șterge căutarea"
              onPress={() => {
                setSearchInput('');
                setSearchQuery('');
              }}
              hitSlop={10}
              style={({ pressed }) => ({ opacity: pressed ? 0.5 : 1 })}>
              <MaterialIcon name="clear" size={24} color={colors.onSurfaceVariant} />
            </Pressable>
          ) : null}
        </View>
      </View>

      {!membersQuery.isLoading && totalCount > 0 ? (
        <View style={styles.memberCount}>
          <MaterialIcon name="people" size={20} color={colors.primary} />
          <AppText color={colors.onSurfaceVariant} style={styles.memberCountText}>
            {totalCount} {totalCount === 1 ? 'membru găsit' : 'membri găsiți'}
          </AppText>
        </View>
      ) : null}

      {membersQuery.isLoading ? (
        <View style={styles.center}>
          <ActivityIndicator size="large" color={colors.primary} />
        </View>
      ) : (
        <FlatList
          data={members}
          contentInsetAdjustmentBehavior="automatic"
          keyExtractor={(member) => member.profile.id}
          contentContainerStyle={members.length ? styles.list : styles.emptyList}
          renderItem={({ item }) => (
            <MemberCard
              member={item}
              onPress={() =>
                router.push({
                  pathname: '/member/[memberId]',
                  params: { memberId: item.profile.id },
                })
              }
            />
          )}
          refreshControl={
            <ManualRefreshControl
              tintColor={colors.primary}
              colors={[colors.primary]}
              onRefresh={() => membersQuery.refetch()}
            />
          }
          ListEmptyComponent={
            <View style={styles.empty}>
              {membersQuery.error ? (
                <View style={[styles.errorBox, { backgroundColor: colorWithAlpha(colors.error, 0.1) }]}>
                  <AppText selectable color={colors.error} style={styles.emptyError}>
                    Eroare: {membersQuery.error instanceof Error ? membersQuery.error.message : String(membersQuery.error)}
                  </AppText>
                </View>
              ) : (
                <>
                  <MaterialIcon name="people_outline" size={64} color={colors.onSurfaceVariant} />
                  <AppText variant="titleLarge" style={styles.emptyTitle}>
                    {searchQuery ? 'Niciun rezultat' : 'Niciun membru'}
                  </AppText>
                </>
              )}
            </View>
          }
          ListFooterComponent={
            membersQuery.hasNextPage ? (
              <View style={styles.footer}>
                <Pressable
                  accessibilityRole="button"
                  disabled={membersQuery.isFetchingNextPage}
                  onPress={() => void membersQuery.fetchNextPage()}
                  style={({ pressed }) => [
                    styles.moreButton,
                    {
                      backgroundColor: colors.primaryContainer,
                      opacity: pressed ? 0.72 : 1,
                    },
                  ]}>
                  {membersQuery.isFetchingNextPage ? (
                    <ActivityIndicator color={colors.onPrimaryContainer} />
                  ) : (
                    <>
                      <MaterialIcon name="expand_more" size={18} color={colors.onPrimaryContainer} />
                      <AppText color={colors.onPrimaryContainer} style={styles.moreText}>
                        Încarcă mai mult
                      </AppText>
                    </>
                  )}
                </Pressable>
              </View>
            ) : null
          }
          keyboardDismissMode="on-drag"
          keyboardShouldPersistTaps="handled"
        />
      )}

      {filtersVisible ? <MembersFilterSheet
        visible
        value={filters}
        gyms={lookupsQuery.data?.gyms ?? []}
        plans={lookupsQuery.data?.plans ?? []}
        onClose={() => setFiltersVisible(false)}
        onApply={setFilters}
        onClear={() => setFilters(defaultFilters)}
      /> : null}
    </View>
  );
}

function countActiveFilters(filters: AppliedMemberFilters): number {
  let count = 0;
  if (filters.gymId) count += 1;
  if ((filters.membershipStatus ?? 'all') !== 'all') count += 1;
  if (filters.expiringInDays !== undefined) count += 1;
  if ((filters.frozenStatus ?? 'all') !== 'all') count += 1;
  if (filters.planId) count += 1;
  if (filters.registrationStart && filters.registrationEnd) count += 1;
  if (filters.checkInStart && filters.checkInEnd) count += 1;
  return count;
}

const styles = StyleSheet.create({
  screen: { flex: 1 },
  headerActions: { flexDirection: 'row', alignItems: 'center' },
  filterAction: { padding: 6 },
  filterCount: {
    position: 'absolute',
    right: -2,
    top: -2,
    minWidth: 16,
    minHeight: 16,
    paddingHorizontal: 4,
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
  },
  filterCountText: { fontSize: 10, lineHeight: 14, fontWeight: '700' },
  searchArea: { padding: 16 },
  searchField: {
    minHeight: 56,
    borderWidth: 1,
    borderRadius: 12,
    borderCurve: 'continuous',
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 12,
  },
  searchInput: { flex: 1, minHeight: 54, paddingHorizontal: 12, fontSize: 16 },
  memberCount: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16, paddingVertical: 8 },
  memberCountText: { marginLeft: 8, fontWeight: '500' },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  list: { padding: 16, paddingBottom: 24 },
  emptyList: { flexGrow: 1, padding: 16 },
  empty: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  emptyTitle: { marginTop: 16 },
  errorBox: { borderRadius: 12, padding: 16, width: '100%' },
  emptyError: { textAlign: 'center' },
  footer: { paddingVertical: 16, alignItems: 'center' },
  moreButton: {
    minHeight: 40,
    paddingHorizontal: 20,
    borderRadius: 20,
    borderCurve: 'continuous',
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
  },
  moreText: { fontWeight: '600', marginLeft: 8 },
});
