package com.zhujitown.app

import android.app.Application
import coil.ImageLoader
import coil.ImageLoaderFactory
import coil.disk.DiskCache
import coil.memory.MemoryCache
import okhttp3.OkHttpClient

class App : Application(), ImageLoaderFactory {

    override fun newImageLoader(): ImageLoader = ImageLoader.Builder(this)
        .memoryCache { MemoryCache.Builder(this).maxSizePercent(0.25).build() }
        .diskCache {
            DiskCache.Builder()
                .directory(cacheDir.resolve("image_cache"))
                .maxSizePercent(0.05)
                .build()
        }
        .okHttpClient {
            OkHttpClient.Builder()
                .connectTimeout(java.util.concurrent.TimeUnit.SECONDS.toMillis(20), java.util.concurrent.TimeUnit.MILLISECONDS)
                .readTimeout(java.util.concurrent.TimeUnit.SECONDS.toMillis(60), java.util.concurrent.TimeUnit.MILLISECONDS)
                .build()
        }
        .crossfade(true)
        .build()
}
