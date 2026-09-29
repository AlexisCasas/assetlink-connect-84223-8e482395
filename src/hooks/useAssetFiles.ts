import { useCallback, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import {
  createAssetDownload,
  deleteAssetFile,
  listAssetFiles,
  setAssetPrimaryPhoto,
  uploadAssetFile,
  type AssetUploadStage,
} from '@/lib/assetFiles';
import type { AssetFile, AssetFileKind } from '@/types/assetFile';

// Signed GET URLs live 300 s. They are kept ONLY in React Query's in-memory
// cache, and considered stale a minute before they expire — never written
// to the database, localStorage or sessionStorage.
const SIGNED_URL_STALE_MS = 4 * 60 * 1000;

export const assetFilesQueryKey = (assetId: string | null | undefined) => ['asset-files', assetId ?? null] as const;
const signedUrlQueryKey = (fileId: string | null | undefined) => ['asset-file-url', fileId ?? null] as const;

/** A short-lived signed URL for an AVAILABLE photo (inline). Pass null to
 * disable. `refresh` re-signs it (used once when an <img> fails, e.g. the
 * URL expired while the page stayed open). */
export function useAssetFileUrl(fileId: string | null | undefined) {
  const query = useQuery({
    queryKey: signedUrlQueryKey(fileId),
    enabled: !!fileId,
    staleTime: SIGNED_URL_STALE_MS,
    gcTime: SIGNED_URL_STALE_MS,
    retry: false,
    queryFn: async () => (await createAssetDownload(fileId!)).downloadUrl,
  });
  return { url: query.data ?? null, loading: query.isLoading && !!fileId, error: query.isError, refresh: query.refetch };
}

export interface AssetUploadProgress {
  kind: AssetFileKind;
  fileName: string;
  stage: AssetUploadStage;
}

/** Files of one asset. Pass null as assetId to disable every query (no
 * read permission, or no asset selected). Mutations refresh the list. */
export function useAssetFiles(assetId: string | null | undefined) {
  const queryClient = useQueryClient();
  const [upload, setUpload] = useState<AssetUploadProgress | null>(null);

  const filesQuery = useQuery({
    queryKey: assetFilesQueryKey(assetId),
    enabled: !!assetId,
    queryFn: () => listAssetFiles(assetId!),
  });

  const refresh = useCallback(
    () => queryClient.invalidateQueries({ queryKey: assetFilesQueryKey(assetId) }),
    [queryClient, assetId],
  );

  const uploadMutation = useMutation({
    mutationFn: async ({ kind, file }: { kind: AssetFileKind; file: File }) => {
      setUpload({ kind, fileName: file.name, stage: 'preparing' });
      return uploadAssetFile(assetId!, kind, file, (stage) => setUpload({ kind, fileName: file.name, stage }));
    },
    // Success or failure, always leave the loading state and re-read the
    // real metadata (a failed upload may have left a `failed` row).
    onSettled: async () => {
      setUpload(null);
      await refresh();
    },
  });

  const deleteMutation = useMutation({
    mutationFn: (fileId: string) => deleteAssetFile(fileId),
    onSettled: async (_data, _error, fileId) => {
      queryClient.removeQueries({ queryKey: signedUrlQueryKey(fileId) });
      await refresh();
    },
  });

  const primaryMutation = useMutation({
    mutationFn: (fileId: string) => setAssetPrimaryPhoto(fileId),
    onSettled: () => refresh(),
  });

  const files: AssetFile[] = filesQuery.data ?? [];
  const available = files.filter((file) => file.status === 'available');
  return {
    files,
    photos: available.filter((file) => file.kind === 'photo'),
    documents: available.filter((file) => file.kind === 'document'),
    /** pending / failed / deleting — only returned to users who can manage. */
    operational: files.filter((file) => file.status !== 'available'),
    primaryPhoto: available.find((file) => file.kind === 'photo' && file.isPrimary) ?? null,
    loading: filesQuery.isLoading && !!assetId,
    error: filesQuery.isError ? 'No se pudieron cargar los archivos del activo.' : null,
    refresh,
    upload,
    uploadFile: uploadMutation.mutateAsync,
    uploading: uploadMutation.isPending,
    deleteFile: deleteMutation.mutateAsync,
    deletingId: deleteMutation.isPending ? deleteMutation.variables ?? null : null,
    setPrimary: primaryMutation.mutateAsync,
    settingPrimaryId: primaryMutation.isPending ? primaryMutation.variables ?? null : null,
  };
}

export type UseAssetFilesResult = ReturnType<typeof useAssetFiles>;
