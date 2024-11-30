import gulp from 'gulp';
import browserSync from 'browser-sync';
import plumber from 'gulp-plumber';
import rename from 'gulp-rename';
import sourcemaps from 'gulp-sourcemaps';
import * as sassModule from 'sass';
import gulpSass from 'gulp-sass';
import csslint from 'gulp-csslint';
import autoprefixer from 'gulp-autoprefixer';
import cssComb from 'gulp-csscomb';
import cmq from 'gulp-merge-media-queries';
import cleanCss from 'gulp-clean-css';
import babel from 'gulp-babel';
import jshint from 'gulp-jshint';
import browserify from 'gulp-browserify';
import uglify from 'gulp-uglify';
import concat from 'gulp-concat';
import imagemin from 'gulp-imagemin';
import cache from 'gulp-cache';
import iconfont from 'gulp-iconfont';
import consolidate from 'gulp-consolidate';
import notify from 'gulp-notify';

const sass = gulpSass(sassModule); // Initialize gulp-sass with dart-sass
const reload = browserSync.create().reload;

// Task: Sass
export function sassTask() {
    return gulp.src(['app/css/**/*.sass'])
        .pipe(plumber())
        .pipe(sourcemaps.init())
        .pipe(sass())
        .pipe(autoprefixer())
        .pipe(cssComb())
        .pipe(cmq({ log: true }))
        .pipe(csslint())
        .pipe(csslint.formatter())
        .pipe(concat('style.css'))
        .pipe(gulp.dest('dist/css'))
        .pipe(rename({ suffix: '.min' }))
        .pipe(cleanCss())
        .pipe(sourcemaps.write())
        .pipe(gulp.dest('dist/css'))
        .pipe(reload({ stream: true }))
        .pipe(notify({ message: 'CSS task finished', onLast: true }));
}

// Task: Babel
export function babelTask() {
    return gulp.src(['app/js/**/*.js'])
        .pipe(plumber())
        .pipe(sourcemaps.init())
        .pipe(babel())
        .pipe(concat('script.js'))
        .pipe(jshint())
        .pipe(jshint.reporter('default'))
        .pipe(browserify())
        .pipe(gulp.dest('dist/js'))
        .pipe(rename({ suffix: '.min' }))
        .pipe(uglify())
        .pipe(sourcemaps.write())
        .pipe(gulp.dest('dist/js'))
        .pipe(reload({ stream: true }))
        .pipe(notify({ message: 'JS task finished', onLast: true }));
}

// Task: HTML
export function htmlTask() {
    return gulp.src(['app/**/*.html'])
        .pipe(plumber()) // Handles errors
        .pipe(gulp.dest('dist/')) // Output destination for processed files
        .pipe(reload({ stream: true })) // Reload browser-sync
        .pipe(notify({ message: 'HTML task finished', onLast: true })); // Notify on completion
}


// Task: Images
export function imageTask() {
    return gulp.src(['app/images/**/*'])
        .pipe(plumber()) // Handles errors
        .pipe(cache(imagemin({ verbose: true }))) // Optimizes images
        .pipe(gulp.dest('dist/images')) // Output directory
        .pipe(reload({ stream: true })) // Reload browser-sync
        .pipe(notify({ message: 'Image task finished', onLast: true })); // Notify on completion
}



// Watch Task
function watchFiles() {
    browserSync.init({ server: "app/" });
    gulp.watch('app/js/**/*.js', babelTask);
    gulp.watch('app/css/**/*.sass', sassTask);
    gulp.watch('app/**/*.html', htmlTask);
    gulp.watch('app/images/**/*', imageTask);
}

// Default Task
export default gulp.series(
    gulp.parallel(sassTask, babelTask, htmlTask, imageTask),
    watchFiles
);
