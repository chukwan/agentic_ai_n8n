/* eslint-disable @typescript-eslint/no-var-requires */
const gulp = require('gulp');
const rename = require('gulp-rename');
const replace = require('gulp-replace');
const svgmin = require('gulp-svgmin');

/**
 * Builds the icons. Specifically, takes the SVG files, optimizes
 * them using `svgo` and renames them using the following pattern:
 * `[name].credentials.svg` -> `[name]Credentials.svg`
 * `[name].node.svg` -> `[name].svg`
 */
function buildIcons() {
	return gulp
		.src(['nodes/**/*.node.svg', 'credentials/**/*.credentials.svg'])
		.pipe(svgmin())
		.pipe(
			rename((path) => {
				if (path.basename.endsWith('.node')) {
					path.basename = path.basename.replace('.node', '');
				} else if (path.basename.endsWith('.credentials')) {
					path.basename = path.basename.replace('.credentials', 'Credentials');
				}
			}),
		)
		.pipe(gulp.dest('dist/icons'));
}

/**
 * Fixes the imports for the `dist` folder. Specifically, changes
 * `file:icon.svg` to `file:icons/icon.svg`.
 */
function fixImports() {
	return gulp
		.src(['dist/**/*.js'])
		.pipe(replace(/file:(.*)\.svg/g, 'file:icons/$1.svg'))
		.pipe(gulp.dest('dist'));
}

exports.build = gulp.series(buildIcons, fixImports);
exports['build:icons'] = buildIcons;