i18n = import('i18n')

add_project_arguments(f'-DGETTEXT_PACKAGE="@vlc_package_name@"',
	language: ['c', 'cpp', 'objc'])
# Keep the same xgettext keywords as po/Makevars (autotools)
i18n.gettext(vlc_package_name,
	args: [
		'--keyword=_',
		'--keyword=N_',
		'--keyword=_NS',
		'--keyword=qtr:1',
		'--keyword=qtr:1,2,3t',
		'--keyword=qsTr:1,1t',
		'--keyword=qsTr:1,2,3t',
		'--keyword=Q_',
		'--language=C++',
		'--keyword=vlc_ngettext:1,2',
		'--keyword=vlc_pgettext:1c,2',
		'--keyword=_PNS:1c,2',
		'--add-comments=xgettext:',
		'--from-code=UTF-8',
	],
	install_dir: localedir_path)

# Check that po/POTFILES.in lists all the files with translatable strings
test('potfiles', find_program('python3'),
    args: [files('check_potfiles.py'), meson.project_source_root()],
    suite: 'po')
